#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define sv_is_glob(sv) (SvTYPE(sv) == SVt_PVGV)
#define sv_is_regexp(sv) (SvTYPE(sv) == SVt_REGEXP)
#define sv_is_string(sv) \
	(!sv_is_glob(sv) && !sv_is_regexp(sv) && \
	 (SvFLAGS(sv) & (SVf_IOK|SVf_NOK|SVf_POK|SVp_IOK|SVp_NOK|SVp_POK)))

#define mkLISTOP(t, f, s, l) THX_mkLISTOP(aTHX_ (t), (f), (s), (l))
static OP *
THX_mkLISTOP(pTHX_ U32 type, OP *first, OP *sib, OP *last)
{
    LISTOP *listop;
    NewOp(1103, listop, 1, LISTOP);
    listop->op_type     = (OPCODE)type;
    listop->op_flags    = OPf_KIDS;
    listop->op_first    = first;
    first->op_sibling   = sib;
    sib->op_sibling     = last;
    listop->op_last     = last;
    return (OP *)listop;
}

static SV *hintkey_method_sv;
static int (*next_keyword_plugin)(pTHX_ char *, STRLEN, OP **);

/* low-level parser helpers */

#define PL_bufptr (PL_parser->bufptr)
#define PL_bufend (PL_parser->bufend)

/*  parse var 
#define parse_var() THX_parse_var(aTHX)
static OP *THX_parse_var(pTHX)
{
	char *s = PL_bufptr;
	char *start = s;
	PADOFFSET varpos;
	OP *padop;
	if(*s != '$') croak("RPN syntax error");
	while(1) {
		char c = *++s;
		if(!isALNUM(c)) break;
	}
	if(s-start < 2) croak("RPN syntax error");
	lex_read_to(s);
	{
		*/
/* because pad_findmy() doesn't really use length yet */
	/*
		SV *namesv = sv_2mortal(newSVpvn(start, s-start));
		varpos = pad_findmy(SvPVX(namesv), s-start, 0);
	}
	if(varpos == NOT_IN_PAD || PAD_COMPNAME_FLAGS_isOUR(varpos))
		croak("RPN only supports \"my\" variables");
	padop = newOP(OP_PADSV, 0);
	padop->op_targ = varpos;
	return padop;
}
*/

/* Parse method name */
#define parse_method_name() THX_parse_method_name(aTHX)
static OP *THX_parse_method_name(pTHX)
{
	char *s = PL_bufptr;
	char *start = s;
    SV *name;

    lex_read_space(0);
    
	while(1) {
        char c = *++s;        
        if (isSPACE(c)) {
            break;
        }
        else if(!(isALNUM(c) || c == '_')) {
            croak("Invalid character in method name");
        }
    }

	if(s-start < 2) croak("no method name");
    lex_read_to(s);

    return newSVOP(OP_CONST, 0, newSVpvn(start, s-start));
}

#define parse_keyword_method() THX_parse_keyword_method(aTHX)
static OP *THX_parse_keyword_method(pTHX)
{
    OP *stmts, *block, *name, *final;
	SV *sub;

 	I32 scope;// = PL_scopestack;

    name = parse_method_name();

	start_subparse(FALSE, 0);
	SAVEFREESV(PL_compcv);
	SvREFCNT_inc_simple_void(PL_compcv);	
	scope = Perl_block_start(TRUE);
	start_subparse(FALSE, 0);	
    stmts = parse_block(0);
	block = Perl_block_end(scope, stmts);
	PL_parser->expect = XSTATE;

	sub = (SV *)newATTRSUB(scope, name, NULL, NULL, block);

	return newUNOP( OP_REFGEN,
		newSVOP(OP_ANONCODE, 0, sub), name);

//	return newOP(OP_NULL, 0);
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

