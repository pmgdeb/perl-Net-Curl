/* vim: ts=4:sw=4:fdm=marker: */

/*
 * Perl interface for libcurl. Check out the file README for more info.
 */

/*
 * Copyright (C) 2000, 2001, 2002, 2005, 2008 Daniel Stenberg, Cris Bailiff, et al.
 * Copyright (C) 2011 Przemyslaw Iskra.
 * You may opt to use, copy, modify, merge, publish, distribute and/or
 * sell copies of the Software, and permit persons to whom the
 * Software is furnished to do so, under the terms of the MPL or
 * the MIT/X-derivate licenses. You may pick one of these licenses.
 */
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <curl/curl.h>
#include <curl/easy.h>
#include <curl/multi.h>
#include "const-defenums-h.inc"
#include "const-c.inc"

#ifndef Newx
# define Newx(v,n,t)    New(0,v,n,t)
# define Newxc(v,n,t,c) Newc(0,v,n,t,c)
# define Newxz(v,n,t)   Newz(0,v,n,t)
#endif

#ifndef hv_stores
# define hv_stores(hv,key,val) hv_store( hv, key, sizeof( key ) - 1, val, 0 )
#endif

typedef struct {
	/* function that will be called */
	SV *func;

	/* user data */
	SV *data;
} callback_t;

typedef struct perl_curl_easy_s perl_curl_easy_t;
typedef struct perl_curl_form_s perl_curl_form_t;
typedef struct perl_curl_share_s perl_curl_share_t;
typedef struct perl_curl_multi_s perl_curl_multi_t;

static struct curl_slist *
perl_curl_array2slist( pTHX_ struct curl_slist *slist, SV *arrayref )
{
	AV *array;
	int array_len, i;

	if ( !SvOK( arrayref ) || !SvROK( arrayref ) )
		croak( "not an array" );

	array = (AV *) SvRV( arrayref );
	array_len = av_len( array );

	for ( i = 0; i <= array_len; i++ ) {
		SV **sv;
		char *string;

		sv = av_fetch( array, i, 0 );
		if ( !SvOK( *sv ) )
			continue;
		string = SvPV_nolen( *sv );
		slist = curl_slist_append( slist, string );
	}

	return slist;
}

typedef struct optionll_s optionll_t;
struct optionll_s {
	/* next in the linked list */
	optionll_t *next;

	/* curl option it belongs to */
	int option;

	/* the actual data */
	void *data;
};

#if 0
static void **
perl_curl_optionll_get( pTHX_ optionll_t *start, int option )
{
	optionll_t *now = start;

	if ( now == NULL )
		return NULL;

	while ( now ) {
		if ( now->option == option )
			return &(now->data);
		if ( now->option > option )
			return NULL;
		now = now->next;
	}

	return NULL;
}
#endif


static void *
perl_curl_optionll_add( pTHX_ optionll_t **start, int option )
{
	optionll_t **now = start;
	optionll_t *tmp = NULL;

	while ( *now ) {
		if ( (*now)->option == option )
			return &( (*now)->data );
		if ( (*now)->option > option )
			break;
		now = &( (*now)->next );
	}

	tmp = *now;
	Newx( *now, 1, optionll_t );
	(*now)->next = tmp;
	(*now)->option = option;
	(*now)->data = NULL;

	return &( (*now)->data );
}

static void *
perl_curl_optionll_del( pTHX_ optionll_t **start, int option )
{
	optionll_t **now = start;

	while ( *now ) {
		if ( (*now)->option == option ) {
			void *ret = (*now)->data;
			optionll_t *tmp = *now;
			*now = (*now)->next;
			Safefree( tmp );
			return ret;
		}
		if ( (*now)->option > option )
			return NULL;
		now = &( (*now)->next );
	}
	return NULL;
}


static const MGVTBL perl_curl_vtbl = { NULL };

static void
perl_curl_setptr( pTHX_ SV *self, void *ptr )
{
	MAGIC *mg;

	mg = sv_magicext( SvRV( self ), 0, PERL_MAGIC_ext,
		&perl_curl_vtbl, (const char *) ptr, 0 );
	mg->mg_flags |= MGf_DUP;
}

static void *
perl_curl_getptr( pTHX_ SV *self )
{
	MAGIC *mg;

	if ( !self )
		croak( "self is null\n" );

	if ( !SvOK( self ) )
		croak( "self not OK\n" );

	if ( !SvROK( self ) )
		croak( "self not ROK\n" );

	if ( !sv_isobject( self ) )
		croak( "self is not an object" );

	for ( mg = SvMAGIC( SvRV( self ) ); mg != NULL; mg = mg->mg_moremagic ) {
		if ( mg->mg_type == PERL_MAGIC_ext && mg->mg_virtual == &perl_curl_vtbl )
			return mg->mg_ptr;
	}

	croak( "object does not have required pointer" );
}

typedef perl_curl_easy_t *WWW__CurlOO__Easy;
typedef perl_curl_form_t *WWW__CurlOO__Form;
typedef perl_curl_multi_t *WWW__CurlOO__Multi;
typedef perl_curl_share_t *WWW__CurlOO__Share;

/* default base object */
#define HASHREF_BY_DEFAULT		newRV_noinc( sv_2mortal( (SV *) newHV() ) )

#include "curloo-Easy-c.inc"
#include "curloo-Form-c.inc"
#include "curloo-Multi-c.inc"
#include "curloo-Share-c.inc"

MODULE = WWW::CurlOO	PACKAGE = WWW::CurlOO		PREFIX = curl_

BOOT:
	/* FIXME: does this need a mutex for ithreads? */
	curl_global_init( CURL_GLOBAL_ALL );

PROTOTYPES: ENABLE

INCLUDE: const-curl-xs.inc

void
curl__global_cleanup()
	CODE:
		curl_global_cleanup();

time_t
curl_getdate( timedate )
	char *timedate
	CODE:
		RETVAL = curl_getdate( timedate, NULL );
	OUTPUT:
		RETVAL

char *
curl_version()
	CODE:
		RETVAL = curl_version();
	OUTPUT:
		RETVAL


SV *
curl_version_info()
	PREINIT:
		const curl_version_info_data *vi;
		HV *ret;
	CODE:
		/* {{{ */
		vi = curl_version_info( CURLVERSION_NOW );
		if ( vi == NULL )
			croak( "curl_version_info() returned NULL\n" );
		ret = newHV();

		(void) hv_stores( ret, "age", newSViv( vi->age ) );
		if ( vi->age >= CURLVERSION_FIRST ) {
			if ( vi->version )
				(void) hv_stores( ret, "version", newSVpv( vi->version, 0 ) );
			(void) hv_stores( ret, "version_num", newSVuv( vi->version_num ) );
			if ( vi->host )
				(void) hv_stores( ret, "host", newSVpv( vi->host, 0 ) );
			(void) hv_stores( ret, "features", newSViv( vi->features ) );
			if ( vi->ssl_version )
				(void) hv_stores( ret, "ssl_version", newSVpv( vi->ssl_version, 0 ) );
			(void) hv_stores( ret, "ssl_version_num", newSViv( vi->ssl_version_num ) );
			if ( vi->libz_version )
				(void) hv_stores( ret, "libz_version", newSVpv( vi->libz_version, 0 ) );
			if ( vi->protocols ) {
				const char * const *p = vi->protocols;
				AV *prot;
				prot = (AV *) sv_2mortal( (SV *) newAV() );
				while ( *p != NULL ) {
					av_push( prot, newSVpv( *p, 0 ) );
					p++;
				}

				(void) hv_stores( ret, "protocols", newRV( (SV*) prot ) );
			}
		}
		if ( vi->age >= CURLVERSION_SECOND ) {
			if ( vi->ares )
				(void) hv_stores( ret, "ares", newSVpv( vi->ares, 0 ) );
			(void) hv_stores( ret, "ares_num", newSViv( vi->ares_num ) );
		}
		if ( vi->age >= CURLVERSION_THIRD ) {
			if ( vi->libidn )
				(void) hv_stores( ret, "libidn", newSVpv( vi->libidn, 0 ) );
		}
#ifdef CURLVERSION_FOURTH
		if ( vi->age >= CURLVERSION_FOURTH ) {
			(void) hv_stores( ret, "iconv_ver_num", newSViv( vi->iconv_ver_num ) );
			if ( vi->libssh_version )
				(void) hv_stores( ret, "libssh_version", newSVpv( vi->libssh_version, 0 ) );
		}
#endif

		RETVAL = newRV( (SV *) ret );
		/* }}} */
	OUTPUT:
		RETVAL


INCLUDE: curloo-Easy-xs.inc
INCLUDE: curloo-Form-xs.inc
INCLUDE: curloo-Multi-xs.inc
INCLUDE: curloo-Share-xs.inc
