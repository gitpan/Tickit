/*  You may distribute under the terms of either the GNU General Public License
 *  or the Artistic License (the same terms as Perl itself)
 *
 *  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk
 */


#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <wchar.h>

/* For pre-5.14 source compatibility */
#ifndef UNICODE_WARN_ILLEGAL_INTERCHANGE
#   define UNICODE_WARN_ILLEGAL_INTERCHANGE 0
#   define UTF8_DISALLOW_SURROGATE 0
#   define UTF8_WARN_SURROGATE 0
#   define UTF8_DISALLOW_FE_FF 0
#   define UTF8_WARN_FE_FF 0
#   define UTF8_WARN_NONCHAR 0
#endif

MODULE = Tickit::Utils      PACKAGE = Tickit::Utils

int textwidth(str)
    SV *str
  INIT:
    char *s, *e;

  CODE:
    RETVAL = 0;
    s = SvPVutf8_nolen(str);
    e = SvEND(str);

    while(s < e) {
      STRLEN len;
      UV ord = utf8n_to_uvchr(s, e-s, &len, (UTF8_DISALLOW_SURROGATE
                                               |UTF8_WARN_SURROGATE
                                               |UTF8_DISALLOW_FE_FF
                                               |UTF8_WARN_FE_FF
                                               |UTF8_WARN_NONCHAR));
      int width = wcwidth(ord);
      if(width == -1)
        XSRETURN_UNDEF;

      s += len;
      RETVAL += width;
    }

  OUTPUT:
    RETVAL

void chars2cols(str,...)
    SV *str;
  INIT:
    char *s, *e;
    char cp = 0, col = 0;
    int i;

  PPCODE:
    s = SvPVutf8_nolen(str);
    e = SvEND(str);

    EXTEND(SP, items - 1);

    for(i = 1; i < items; i++ ) {
      int thiscp = SvUV(ST(i));
      if(thiscp < cp)
        croak("chars2cols requires a monotonically-increasing list of character numbers; %d is not greater than %d\n",
          thiscp, cp);

      while(s < e && cp < thiscp) {
        STRLEN len;
        UV ord = utf8n_to_uvchr(s, e-s, &len, (UTF8_DISALLOW_SURROGATE
                                                 |UTF8_WARN_SURROGATE
                                                 |UTF8_DISALLOW_FE_FF
                                                 |UTF8_WARN_FE_FF
                                                 |UTF8_WARN_NONCHAR));

        int width = wcwidth(ord);
        if(width == -1)
          (GIMME_V == G_ARRAY) ? XSRETURN(0) : XSRETURN_UNDEF;

        s += len;
        cp += 1;
        col += width;
      }

      mPUSHu(col);

      if(GIMME_V != G_ARRAY)
        XSRETURN(1);
    }

    XSRETURN(items - 1);

void cols2chars(str,...)
    SV *str;
  INIT:
    char *s, *e;
    char cp = 0, col = 0;
    int i;

  PPCODE:
    s = SvPVutf8_nolen(str);
    e = SvEND(str);

    EXTEND(SP, items - 1);

    for(i = 1; i < items; i++ ) {
      int thiscol = SvUV(ST(i));
      if(thiscol < col)
        croak("cols2chars requires a monotonically-increasing list of column numbers; %d is not greater than %d\n",
          thiscol, col);

      while(s < e) {
        STRLEN len;
        UV ord = utf8n_to_uvchr(s, e-s, &len, (UTF8_DISALLOW_SURROGATE
                                                 |UTF8_WARN_SURROGATE
                                                 |UTF8_DISALLOW_FE_FF
                                                 |UTF8_WARN_FE_FF
                                                 |UTF8_WARN_NONCHAR));

        int width = wcwidth(ord);
        if(width == -1)
          (GIMME_V == G_ARRAY) ? XSRETURN(0) : XSRETURN_UNDEF;

        if(col + width > thiscol)
          break;

        s += len;
        cp += 1;
        col += width;
      }

      mPUSHu(cp);

      if(GIMME_V != G_ARRAY)
        XSRETURN(1);
    }

    XSRETURN(items - 1);
