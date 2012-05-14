/*  You may distribute under the terms of either the GNU General Public License
 *  or the Artistic License (the same terms as Perl itself)
 *
 *  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk
 */


#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <tickit.h>

static struct {
  char *name;
  TickitPenAttr attr;
} attrs[] = {
  { "fg",     TICKIT_PEN_FG },
  { "bg",     TICKIT_PEN_BG },
  { "b",      TICKIT_PEN_BOLD },
  { "u",      TICKIT_PEN_UNDER },
  { "i",      TICKIT_PEN_ITALIC },
  { "rv",     TICKIT_PEN_REVERSE },
  { "strike", TICKIT_PEN_STRIKE },
  { "af",     TICKIT_PEN_ALTFONT },
};

static TickitPen *pen_from_args(SV **args, int argcount)
{
  int i;
  TickitPen *pen = tickit_pen_new();

  for(i = 0; i < argcount; i += 2) {
    char *name  = SvPV_nolen(args[i]);
    SV   *value = args[i+1];

    int j;
    for(j = 0; j < sizeof(attrs)/sizeof(attrs[0]); j++) {
      if(strcmp(name, attrs[j].name) != 0)
        continue;

      switch(tickit_pen_attrtype(attrs[j].attr)) {
      case TICKIT_PENTYPE_INT:
        tickit_pen_set_int_attr(pen, attrs[j].attr, SvOK(value) ? SvIV(value) : -1);
        break;
      case TICKIT_PENTYPE_BOOL:
        tickit_pen_set_bool_attr(pen, attrs[j].attr, SvOK(value) ? SvIV(value) : 0);
        break;
      }

      break;
    }
  }

  return pen;
}

typedef struct Tickit__Term {
  TickitTerm *tt;
  SV         *input_handle;
  SV         *output_handle;
  CV         *output_func;

  SV         *self;
  CV         *on_resize;
  CV         *on_key;
  CV         *on_mouse;
} *Tickit__Term;

static void term_event_fn(TickitTerm *tt, TickitEventType ev, TickitEvent *args, void *data)
{
  Tickit__Term self = data;

  if(ev & TICKIT_EV_RESIZE) {
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 3);
    PUSHs(self->self); // not mortal
    mPUSHi(args->lines);
    mPUSHi(args->cols);
    PUTBACK;

    call_sv((SV*)(self->on_resize), G_VOID);

    FREETMPS;
    LEAVE;
  }

  if(ev & TICKIT_EV_KEY) {
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 3);
    PUSHs(self->self); // not mortal
    switch(args->type) {
      case TICKIT_KEYEV_KEY:  mPUSHp("key",  3); break;
      case TICKIT_KEYEV_TEXT: mPUSHp("text", 4); break;
    }
    mPUSHp(args->str, strlen(args->str));
    PUTBACK;

    call_sv((SV*)(self->on_key), G_VOID);

    FREETMPS;
    LEAVE;
  }

  if(ev & TICKIT_EV_MOUSE) {
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 5);
    PUSHs(self->self); // not mortal
    switch(args->type) {
      case TICKIT_MOUSEEV_PRESS:   mPUSHp("press",   5); break;
      case TICKIT_MOUSEEV_DRAG:    mPUSHp("drag",    4); break;
      case TICKIT_MOUSEEV_RELEASE: mPUSHp("release", 7); break;
      case TICKIT_MOUSEEV_WHEEL:   mPUSHp("wheel",   5); break;
    }
    if(args->type == TICKIT_MOUSEEV_WHEEL) {
      switch(args->button) {
        case TICKIT_MOUSEWHEEL_UP:   mPUSHp("up",   2); break;
        case TICKIT_MOUSEWHEEL_DOWN: mPUSHp("down", 4); break;
      }
    }
    else {
      mPUSHi(args->button);
    }
    mPUSHi(args->line);
    mPUSHi(args->col);
    PUTBACK;

    call_sv((SV*)(self->on_mouse), G_VOID);

    FREETMPS;
    LEAVE;
  }
}

static void term_output_fn(TickitTerm *tt, const char *bytes, size_t len, void *user)
{
  Tickit__Term self = user;

  dSP;
  ENTER;
  SAVETMPS;

  PUSHMARK(SP);
  EXTEND(SP, 1);
  mPUSHp(bytes, len);
  PUTBACK;

  call_sv((SV*)(self->output_func), G_VOID);

  FREETMPS;
  LEAVE;
}

MODULE = Tickit             PACKAGE = Tickit::Term

SV *
_new(package,termtype)
  char *termtype;
  INIT:
    Tickit__Term self;
  CODE:
    Newx(self, 1, struct Tickit__Term);
    RETVAL = newSV(0);
    sv_setref_pv(RETVAL, "Tickit::Term", self);
    self->self = newSVsv(RETVAL);

    self->tt = tickit_term_new_for_termtype(termtype);
    self->input_handle  = NULL;
    self->output_handle = NULL;
    self->output_func = NULL;

    self->on_resize = NULL;
    self->on_key    = NULL;
    self->on_mouse  = NULL;

  OUTPUT:
    RETVAL

void
DESTROY(self)
  Tickit::Term  self
  CODE:
    /*
     * destroy TickitTerm first in case it's still using output_handle/func
     */
    tickit_term_destroy(self->tt);

    if(self->input_handle)
      SvREFCNT_dec(self->input_handle);

    if(self->output_handle)
      SvREFCNT_dec(self->output_handle);

    if(self->output_func)
      SvREFCNT_dec(self->output_func);

    if(self->on_resize)
      SvREFCNT_dec(self->on_resize);

    if(self->on_key)
      SvREFCNT_dec(self->on_key);

    if(self->on_mouse)
      SvREFCNT_dec(self->on_mouse);

    Safefree(self);

SV *
get_input_handle(self,handle)
  Tickit::Term  self
  CODE:
    sv_setsv(RETVAL, self->input_handle);

void
set_input_handle(self,handle)
  Tickit::Term  self
  SV           *handle
  CODE:
    if(self->input_handle)
      SvREFCNT_dec(self->input_handle);

    self->input_handle = SvREFCNT_inc(SvRV(handle));
    tickit_term_set_input_fd(self->tt, PerlIO_fileno(IoIFP(sv_2io(handle))));

SV *
get_output_handle(self,handle)
  Tickit::Term  self
  CODE:
    sv_setsv(RETVAL, self->output_handle);

void
set_output_handle(self,handle)
  Tickit::Term  self
  SV           *handle
  CODE:
    if(self->output_handle)
      SvREFCNT_dec(self->output_handle);

    self->output_handle = SvREFCNT_inc(SvRV(handle));
    tickit_term_set_output_fd(self->tt, PerlIO_fileno(IoIFP(sv_2io(handle))));

void
set_output_func(self,func)
  Tickit::Term  self
  CV           *func
  CODE:
    if(self->output_func)
      SvREFCNT_dec(self->output_func);

    self->output_func = (CV*)SvREFCNT_inc(func);
    tickit_term_set_output_func(self->tt, term_output_fn, self);

void
get_size(self)
  Tickit::Term  self
  INIT:
    int lines, cols;
  PPCODE:
    tickit_term_get_size(self->tt, &lines, &cols);
    EXTEND(SP, 2);
    mPUSHi(lines);
    mPUSHi(cols);
    XSRETURN(2);

void
set_size(self,lines,cols)
  Tickit::Term  self
  int           lines
  int           cols
  CODE:
    tickit_term_set_size(self->tt, lines, cols);

void
refresh_size(self)
  Tickit::Term  self
  CODE:
    tickit_term_refresh_size(self->tt);

void
set_on_resize(self,code)
  Tickit::Term  self
  CV           *code
  CODE:
    if(self->on_resize)
      SvREFCNT_dec(self->on_resize);

    tickit_term_bind_event(self->tt, TICKIT_EV_RESIZE, term_event_fn, self);
    self->on_resize = (CV*)SvREFCNT_inc(code);

void
set_on_key(self,code)
  Tickit::Term  self
  CV           *code
  CODE:
    if(self->on_key)
      SvREFCNT_dec(self->on_key);

    tickit_term_bind_event(self->tt, TICKIT_EV_KEY, term_event_fn, self);
    self->on_key = (CV*)SvREFCNT_inc(code);

void
set_on_mouse(self,code)
  Tickit::Term  self
  CV           *code
  CODE:
    if(self->on_mouse)
      SvREFCNT_dec(self->on_mouse);

    tickit_term_bind_event(self->tt, TICKIT_EV_MOUSE, term_event_fn, self);
    self->on_mouse = (CV*)SvREFCNT_inc(code);

void
input_push_bytes(self,bytes)
  Tickit::Term  self
  SV           *bytes
  INIT:
    char   *str;
    STRLEN  len;
  CODE:
    str = SvPV(bytes, len);
    tickit_term_input_push_bytes(self->tt, str, len);

void
input_readable(self)
  Tickit::Term  self
  CODE:
    tickit_term_input_readable(self->tt);

void
input_wait(self)
  Tickit::Term  self
  CODE:
    tickit_term_input_wait(self->tt);

SV *
check_timeout(self)
  Tickit::Term  self
  INIT:
    int msec;
  CODE:
    msec = tickit_term_input_check_timeout(self->tt);
    RETVAL = newSV(0);
    if(msec >= 0)
      sv_setnv(RETVAL, msec / 1000.0);
  OUTPUT:
    RETVAL

void
print(self,text)
  Tickit::Term  self
  SV           *text
  CODE:
    tickit_term_print(self->tt, SvPVutf8_nolen(text));

void
goto(self,line,col)
  Tickit::Term  self
  SV           *line
  SV           *col
  CODE:
    tickit_term_goto(self->tt, SvOK(line) ? SvIV(line) : -1, SvOK(col) ? SvIV(col) : -1);

void
move(self,downward,rightward)
  Tickit::Term  self
  SV           *downward
  SV           *rightward
  CODE:
    tickit_term_move(self->tt, SvOK(downward) ? SvIV(downward) : 0, SvOK(rightward) ? SvIV(rightward) : 0);

int
scrollrect(self,top,left,lines,cols,downward,rightward)
  Tickit::Term  self
  int           top
  int           left
  int           lines
  int           cols
  int           downward
  int           rightward
  CODE:
    RETVAL = tickit_term_scrollrect(self->tt, top, left, lines, cols, downward, rightward);

void
chpen(self,...)
  Tickit::Term  self
  INIT:
    TickitPen *pen;
  CODE:
    pen = pen_from_args(SP-items+2, items-1);
    tickit_term_chpen(self->tt, pen);
    tickit_pen_destroy(pen);

void
setpen(self,...)
  Tickit::Term  self
  INIT:
    TickitPen *pen;
  CODE:
    pen = pen_from_args(SP-items+2, items-1);
    tickit_term_setpen(self->tt, pen);
    tickit_pen_destroy(pen);

void
clear(self)
  Tickit::Term  self
  CODE:
    tickit_term_clear(self->tt);

void
erasech(self,count,moveend)
  Tickit::Term  self
  int           count
  SV           *moveend
  CODE:
    tickit_term_erasech(self->tt, count, SvOK(moveend) ? SvIV(moveend) : -1);

void
set_mode_altscreen(self,on)
  Tickit::Term  self
  int           on
  CODE:
    tickit_term_set_mode_altscreen(self->tt, on);

void
set_mode_cursorvis(self,on)
  Tickit::Term  self
  int           on
  CODE:
    tickit_term_set_mode_cursorvis(self->tt, on);

void
set_mode_mouse(self,on)
  Tickit::Term  self
  int           on
  CODE:
    tickit_term_set_mode_mouse(self->tt, on);

MODULE = Tickit             PACKAGE = Tickit::Utils

int textwidth(str)
    SV *str
  INIT:
    STRLEN len;
    const char *s;
    TickitStringPos pos, limit;

  CODE:
    RETVAL = 0;

    if(!SvUTF8(str)) {
      str = sv_mortalcopy(str);
      sv_utf8_upgrade(str);
    }

    s = SvPV_const(str, len);

    tickit_stringpos_limit_bytes(&limit, len);
    tickit_string_count(s, &pos, &limit);

    RETVAL = pos.columns;

  OUTPUT:
    RETVAL

void chars2cols(str,...)
    SV *str;
  INIT:
    STRLEN len;
    const char *s;
    int i;
    TickitStringPos pos, limit;

  PPCODE:
    if(!SvUTF8(str)) {
      str = sv_mortalcopy(str);
      sv_utf8_upgrade(str);
    }

    s = SvPV_const(str, len);

    EXTEND(SP, items - 1);

    tickit_stringpos_zero(&pos);
    tickit_stringpos_limit_bytes(&limit, len);

    for(i = 1; i < items; i++ ) {
      limit.codepoints = SvUV(ST(i));
      if(limit.codepoints < pos.codepoints)
        croak("chars2cols requires a monotonically-increasing list of character numbers; %d is not greater than %d\n",
          limit.codepoints, pos.codepoints);

      tickit_string_countmore(s, &pos, &limit);

      mPUSHu(pos.columns);

      if(GIMME_V != G_ARRAY)
        XSRETURN(1);
    }

    XSRETURN(items - 1);

void cols2chars(str,...)
    SV *str;
  INIT:
    STRLEN len;
    const char *s;
    int i;
    TickitStringPos pos, limit;

  PPCODE:
    if(!SvUTF8(str)) {
      str = sv_mortalcopy(str);
      sv_utf8_upgrade(str);
    }

    s = SvPV_const(str, len);

    EXTEND(SP, items - 1);

    tickit_stringpos_zero(&pos);
    tickit_stringpos_limit_bytes(&limit, len);

    for(i = 1; i < items; i++ ) {
      limit.columns = SvUV(ST(i));
      if(limit.columns < pos.columns)
        croak("cols2chars requires a monotonically-increasing list of column numbers; %d is not greater than %d\n",
          limit.columns, pos.columns);

      tickit_string_countmore(s, &pos, &limit);

      mPUSHu(pos.codepoints);

      if(GIMME_V != G_ARRAY)
        XSRETURN(1);
    }

    XSRETURN(items - 1);
