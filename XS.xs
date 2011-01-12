#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define sv_is_glob(sv) (SvTYPE(sv) == SVt_PVGV)
#define sv_is_regexp(sv) (SvTYPE(sv) == SVt_REGEXP)
#define sv_is_string(sv) \
	(!sv_is_glob(sv) && !sv_is_regexp(sv) && \
	 (SvFLAGS(sv) & (SVf_IOK|SVf_NOK|SVf_POK|SVp_IOK|SVp_NOK|SVp_POK)))

static SV *hintkey_method_sv;
static int (*next_keyword_plugin)(pTHX_ char *, STRLEN, OP **);

/* low-level parser helpers */

#define PL_bufptr (PL_parser->bufptr)
#define PL_bufend (PL_parser->bufend)

/* 
 * install stub (stolen from Mouse - xs-src/MouseUtil.xs 
 */

void install_sub(pTHX_ GV* const gv, SV* const code_ref) {
    CV* cv;

    assert(gv != NULL);
    assert(code_ref != NULL);
    assert(isGV(gv));
    assert(IsCodeRef(code_ref));

    if(GvCVu(gv)){ /* delete *slot{gv} to work around "redefine" warning */
        SvREFCNT_dec(GvCV(gv));
        GvCV(gv) = NULL;
    }


    sv_setsv_mg((SV*)gv, code_ref); /* *gv = $code_ref */

    /* name the CODE ref if it's anonymous */
    cv = (CV*)SvRV(code_ref);
    if(CvANON(cv)
        && CvGV(cv) /* a cv under construction has no gv */ ){
        HV* dbsub;

        /* update %DB::sub to make NYTProf happy */
        if((PL_perldb & (PERLDBf_SUBLINE|PERLDB_NAMEANON))
            && PL_DBsub && (dbsub = GvHV(PL_DBsub))
        ){
            /* see Perl_newATTRSUB() in op.c */
            SV* const subname = sv_newmortal();
            HE* orig;

            gv_efullname3(subname, CvGV(cv), NULL);
            orig = hv_fetch_ent(dbsub, subname, FALSE, 0U);
            if(orig){
                gv_efullname3(subname, gv, NULL);
                (void)hv_store_ent(dbsub, subname, HeVAL(orig), 0U);
                SvREFCNT_inc_simple_void_NN(HeVAL(orig));
            }
        }

        CvGV_set(cv, gv);
        CvANON_off(cv);
    }
}

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
	
	return sv_2mortal(newSVpvn(start, s-start));
}

GV *get_slot(SV *method_name, HV *stash)
{
	SV *package_name = newSVpvn_share(HvNAME_get(stash), HvNAMELEN_get(stash), 0U);
	GV *slot;

	slot = gv_fetchpv(
		form("%"SVf"::%"SVf, package_name, method_name), 
		GV_ADDMULTI, SVt_PVCV
	);
	
	if(!slot)
		croak("couldn't get slot");

	return slot;
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
		
		SV *to_inject = newSVpv("{my ($self, ", 0U);
		sv_catsv(to_inject, newSVpvn(start, end-start));
		sv_catpv(to_inject, ") = @_; die 'died parsed sig';\n");
		

		/* chop out sig */
		lex_unstuff(++end);

		return to_inject;
	} else {
		return newSVpv("{ my ($self) = @_; print \"parsed sig!\\n\";", 0U);
	}
}

#define parse_keyword_method() THX_parse_keyword_method(aTHX)
static OP *THX_parse_keyword_method(pTHX)
{
    OP *stmts, *block, *final;
	SV *code, *method_name, *package_name, *inject;
	HV *stash;
	GV *slot;
 	I32 scope;

    method_name = parse_method_name();


	/* inject stack/sig stuff */
	inject = parse_signature();
	lex_read_space(0);
	char *pos = PL_bufptr;
	lex_unstuff(++pos); /* discard '{' */
    lex_read_to(pos);
	lex_stuff_sv(inject, 0U);


    /*printf("%s about to parse: '%s'\n",
        form("%"SVf, method_name), form("%"SVf, newSVpvn(pos, 30)));
*/

	start_subparse(FALSE, 0);
	SAVEFREESV(PL_compcv);
	SvREFCNT_inc_simple_void(PL_compcv);

	scope = Perl_block_start(TRUE);
	start_subparse(FALSE, 0);	

    stmts = ck_entersub_args_list(
            op_scope( parse_block(0) )
    );

	block = Perl_block_end(scope, stmts);
	slot = get_slot(method_name, PL_curstash);
	
	code = (SV *)newATTRSUB(scope, 
		newSVOP(OP_CONST, 0, method_name), NULL, NULL, block);

	install_sub(aTHX_ slot, newRV_inc(code));

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

