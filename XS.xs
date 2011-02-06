#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

static SV *hintkey_method_sv;
static int (*next_keyword_plugin)(pTHX_ char *, STRLEN, OP **);

#define PL_bufptr (PL_parser->bufptr)
#define PL_bufend (PL_parser->bufend)

/* Parse method name */
#define parse_method_name() THX_parse_method_name(aTHX)
SV *THX_parse_method_name(pTHX)
{

    lex_read_space(0);
	char *s = PL_bufptr;
	char *start = s;
    SV *name;

	while(1) {
        char c = *++s;        
        if (isSPACE(c) || c == '(') {
            break;
        }
        else if(!(isALNUM(c) || c == '_')) {
            croak("Invalid character in method name");
        }
    }

	if(s-start < 2) 
		croak("no method name");
    lex_read_to(s);
	
	return newSVpvn(start, s-start);
}


SV *parse_signature(pTHX)
{
	SV *to_inject;
	char *start, *end;
	lex_read_space(0);

	start = PL_bufptr;

	if (*start == '(') {	
		/* read till end of signature */

		end = start;
		while(1) {
			char c = *++end;        
			if (c == ')') {
				break;	
			}	
		}

		start++; /* skip opening brace */
		
		SV *to_inject = newSVpv(" {my ($self, ", 0U);
		sv_catsv(to_inject, newSVpvn(start, end-start));
		sv_catpv(to_inject, ") = @_;\n");
		

		/* chop out sig */
		lex_unstuff(++end);

		return to_inject;
	} else {
		return newSVpv(" { my ($self) = @_;", 0U);
	}
}

#define parse_keyword_method() THX_parse_keyword_method(aTHX)
static OP *THX_parse_keyword_method(pTHX)
{
    OP *block;
	SV *code, *method_name, *sig, *inject;
	GV *slot;
 	I32 scope;

    method_name = parse_method_name();

	/* inject stack/sig stuff */
	sig = parse_signature();
	inject = newSVpv("; sub ", 0U);
	sv_catsv(inject, method_name);
	sv_catsv(inject, sig);

	lex_read_space(0);
	char *pos = PL_bufptr;
	lex_unstuff(++pos); /* discard '{' */
    lex_read_to(pos);

	lex_stuff_sv(inject, 0U);
	
 	return newOP(OP_NULL, 0);
}


/* plugin glue */
static int THX_keyword_active(pTHX_ SV *hintkey_sv)
{
	HE *he;
	if(!GvHV(PL_hintgv)) return 0;
	he = hv_fetch_ent(GvHV(PL_hintgv), hintkey_sv, 0,
				SvSHARED_HASH(hintkey_sv));
	return he && SvTRUE(HeVAL(he));
}

#define keyword_active(hintkey_sv) THX_keyword_active(aTHX_ hintkey_sv)
static void THX_keyword_enable(pTHX_ SV *hintkey_sv)
{
	SV *val_sv = newSViv(1);
	HE *he;
	PL_hints |= HINT_LOCALIZE_HH;
	gv_HVadd(PL_hintgv);
	he = hv_store_ent(GvHV(PL_hintgv),
		hintkey_sv, val_sv, SvSHARED_HASH(hintkey_sv));
	if(he) {
		SV *val = HeVAL(he);
		SvSETMAGIC(val);
	} else {
		SvREFCNT_dec(val_sv);
	}
}

#define keyword_enable(hintkey_sv) THX_keyword_enable(aTHX_ hintkey_sv)
static void THX_keyword_disable(pTHX_ SV *hintkey_sv)
{
	if(GvHV(PL_hintgv)) {
		PL_hints |= HINT_LOCALIZE_HH;
		hv_delete_ent(GvHV(PL_hintgv),
			hintkey_sv, G_DISCARD, SvSHARED_HASH(hintkey_sv));
	}
}

#define keyword_disable(hintkey_sv) THX_keyword_disable(aTHX_ hintkey_sv)
static int my_keyword_plugin(pTHX_
	char *keyword_ptr, STRLEN keyword_len, OP **op_ptr)
{
	if(keyword_len == 6 && strnEQ(keyword_ptr, "method", 6) &&
			keyword_active(hintkey_method_sv)) {
		*op_ptr = parse_keyword_method();
		return KEYWORD_PLUGIN_STMT;
	} else {
		return next_keyword_plugin(aTHX_
				keyword_ptr, keyword_len, op_ptr);
	}
}

MODULE = Method::Signatures::XS PACKAGE = Method::Signatures::XS

BOOT:
	hintkey_method_sv = newSVpvs_share("Method::Signatures::XS/method");
	next_keyword_plugin = PL_keyword_plugin;
	PL_keyword_plugin = my_keyword_plugin;

void
import(SV *classname, ...)
PPCODE:
	keyword_enable(hintkey_method_sv);


void
unimport(SV *classname, ...)
PPCODE:
	keyword_disable(hintkey_method_sv);

