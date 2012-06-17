/*  You may distribute under the terms of either the GNU General Public License
 *  or the Artistic License (the same terms as Perl itself)
 *
 *  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk
 */


#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <tickit.h>

#define streq(a,b) (strcmp(a,b)==0)

/* We need to keep our own pen observer list rather than use libtickit's event
 * binds, because we need to be able to remove them by observer reference
 */
struct PenObserver {
  struct PenObserver *next;
  SV                 *observer;
  SV                 *id;
};

typedef struct Tickit__Pen {
  TickitPen          *pen;
  SV                 *self;
  struct PenObserver *observers;
  int                 event_id;
} *Tickit__Pen;

static TickitPenAttr lookup_pen_attr(const char *name)
{
  switch(name[0]) {
    case 'a':
      return streq(name+1,"f") ? TICKIT_PEN_ALTFONT
                               : -1;
    case 'b':
      return name[1] == 0      ? TICKIT_PEN_BOLD
           : streq(name+1,"g") ? TICKIT_PEN_BG
                               : -1;
    case 'f':
      return streq(name+1,"g") ? TICKIT_PEN_FG
                               : -1;
    case 'i':
      return name[1] == 0      ? TICKIT_PEN_ITALIC
                               : -1;
    case 'r':
      return streq(name+1,"v") ? TICKIT_PEN_REVERSE
                               : -1;
    case 's':
      return streq(name+1,"trike") ? TICKIT_PEN_STRIKE
                               : -1;
    case 'u':
      return name[1] == 0      ? TICKIT_PEN_UNDER
                               : -1;
  }
  return -1;
}

static const char *get_pen_attr_name(TickitPenAttr attr)
{
  switch(attr) {
    case TICKIT_PEN_FG:      return "fg";
    case TICKIT_PEN_BG:      return "bg";
    case TICKIT_PEN_BOLD:    return "b";
    case TICKIT_PEN_UNDER:   return "u";
    case TICKIT_PEN_ITALIC:  return "i";
    case TICKIT_PEN_REVERSE: return "rv";
    case TICKIT_PEN_STRIKE:  return "strike";
    case TICKIT_PEN_ALTFONT: return "af";
  }
  return NULL;
}

static SV *pen_get_attr(TickitPen *pen, TickitPenAttr attr)
{
  switch(tickit_pen_attrtype(attr)) {
  case TICKIT_PENTYPE_BOOL:
    return tickit_pen_get_bool_attr(pen, attr) ? &PL_sv_yes : &PL_sv_no;
  case TICKIT_PENTYPE_INT:
    return newSViv(tickit_pen_get_int_attr(pen, attr));
  case TICKIT_PENTYPE_COLOUR:
    return newSViv(tickit_pen_get_colour_attr(pen, attr));
  }
}

static void pen_set_attr(TickitPen *pen, TickitPenAttr attr, SV *val)
{
  switch(tickit_pen_attrtype(attr)) {
  case TICKIT_PENTYPE_INT:
    tickit_pen_set_int_attr(pen, attr, SvOK(val) ? SvIV(val) : -1);
    break;
  case TICKIT_PENTYPE_BOOL:
    tickit_pen_set_bool_attr(pen, attr, SvOK(val) ? SvIV(val) : 0);
    break;
  case TICKIT_PENTYPE_COLOUR:
    if(!SvPOK(val) && (SvIOK(val) || SvUOK(val) || SvNOK(val)))
      tickit_pen_set_colour_attr(pen, attr, SvIV(val));
    else if(SvPOK(val))
      tickit_pen_set_colour_attr_desc(pen, attr, SvPV_nolen(val));
    else
      tickit_pen_set_colour_attr(pen, attr, -1);
    break;
  }
}

static TickitPen *pen_from_args(SV **args, int argcount)
{
  int i;
  TickitPen *pen = tickit_pen_new();

  for(i = 0; i < argcount; i += 2) {
    const char *name  = SvPV_nolen(args[i]);
    SV         *value = args[i+1];

    TickitPenAttr attr = lookup_pen_attr(name);
    if(attr != -1)
      pen_set_attr(pen, attr, value);
  }

  return pen;
}

static void pen_event_fn(TickitPen *pen, TickitEventType ev, TickitEvent *args, void *data)
{
  Tickit__Pen self = data;

  if(ev & TICKIT_EV_CHANGE) {
    struct PenObserver *node;
    for(node = self->observers; node; node = node->next) {
      dSP;
      ENTER;
      SAVETMPS;

      PUSHMARK(SP);
      EXTEND(SP, 3);
      mPUSHs(newSVsv(node->observer));
      PUSHs(self->self); // not mortal
      PUSHs(node->id);
      PUTBACK;

      call_method("on_pen_changed", G_VOID);

      FREETMPS;
      LEAVE;
    }
  }
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
    PUSHs(sv_2mortal(newSVpvn_utf8(args->str, strlen(args->str), 1)));
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

MODULE = Tickit             PACKAGE = Tickit::Pen

SV *
_new(package)
  char *package
  INIT:
    Tickit__Pen self;
  CODE:
    Newx(self, 1, struct Tickit__Pen);
    RETVAL = newSV(0);
    sv_setref_pv(RETVAL, "Tickit::Pen", self);
    self->self = newSVsv(RETVAL);

    self->pen = tickit_pen_new();
    self->observers = NULL;
  OUTPUT:
    RETVAL

void
DESTROY(self)
  Tickit::Pen self
  CODE:
    tickit_pen_destroy(self->pen);
    SvREFCNT_dec(self->self);
    while(self->observers) {
      struct PenObserver *here = self->observers;
      self->observers = here->next;

      SvREFCNT_dec(here->observer);
      SvREFCNT_dec(here->id);
      Safefree(here);
    }
    Safefree(self);

bool
hasattr(self,attr)
  Tickit::Pen  self
  char        *attr
  INIT:
    TickitPenAttr a;
  CODE:
    if((a = lookup_pen_attr(attr)) == -1)
      XSRETURN_UNDEF;
    RETVAL = tickit_pen_has_attr(self->pen, a);
  OUTPUT:
    RETVAL

SV *
getattr(self,attr)
  Tickit::Pen  self
  char        *attr
  INIT:
    TickitPenAttr a;
  CODE:
    if((a = lookup_pen_attr(attr)) == -1)
      XSRETURN_UNDEF;
    if(!tickit_pen_has_attr(self->pen, a))
      XSRETURN_UNDEF;
    RETVAL = pen_get_attr(self->pen, a);
  OUTPUT:
    RETVAL

void
getattrs(self)
  Tickit::Pen self
  INIT:
    TickitPenAttr a;
    int           count = 0;
  PPCODE:
    for(a = 0; a < TICKIT_N_PEN_ATTRS; a++) {
      if(!tickit_pen_has_attr(self->pen, a))
        continue;

      EXTEND(SP, 2); count += 2;

      /* Because mPUSHp(str,0) creates a 0-length string */
      mPUSHs(newSVpv(get_pen_attr_name(a), 0));
      mPUSHs(pen_get_attr(self->pen, a));
    }
    XSRETURN(count);

void
chattr(self,attr,value)
  Tickit::Pen  self
  char        *attr
  SV          *value
  INIT:
    TickitPenAttr a;
  CODE:
    if((a = lookup_pen_attr(attr)) == -1)
      XSRETURN_UNDEF;
    if(!SvOK(value)) {
      tickit_pen_clear_attr(self->pen, a);
      XSRETURN_UNDEF;
    }
    pen_set_attr(self->pen, a, value);

void
chattrs(self,attrs)
  Tickit::Pen  self
  HV          *attrs
  INIT:
    TickitPenAttr a;
  CODE:
    for(a = 0; a < TICKIT_N_PEN_ATTRS; a++) {
      const char *name = get_pen_attr_name(a);
      SV *val = hv_delete(attrs, name, strlen(name), 0);
      if(!val)
        continue;

      if(!SvOK(val))
        tickit_pen_clear_attr(self->pen, a);
      else
        pen_set_attr(self->pen, a, val);
    }

void
delattr(self,attr)
  Tickit::Pen  self
  char        *attr
  INIT:
    TickitPenAttr a;
  CODE:
    if((a = lookup_pen_attr(attr)) == -1)
      XSRETURN_UNDEF;
    tickit_pen_clear_attr(self->pen, a);

void
copy(self,other,overwrite)
  Tickit::Pen self
  Tickit::Pen other
  int         overwrite
  CODE:
    tickit_pen_copy(self->pen, other->pen, overwrite);

void
add_on_changed(self,observer,id=&PL_sv_undef)
  Tickit::Pen  self
  SV          *observer
  SV          *id
  INIT:
    struct PenObserver *node;
  CODE:
    if(!SvROK(observer))
      croak("Expected observer to be a reference");

    Newx(node, 1, struct PenObserver);
    node->observer = sv_rvweaken(newSVsv(observer));
    node->id       = newSVsv(id);
    node->next     = NULL;

    if(self->observers) {
      struct PenObserver *link = self->observers;
      while(link->next)
        link = link->next;
      link->next = node;
    }
    else {
      self->event_id = tickit_pen_bind_event(self->pen, TICKIT_EV_CHANGE, pen_event_fn, self);
      self->observers = node;
    }

void
remove_on_changed(self,observer)
  Tickit::Pen  self
  SV          *observer
  INIT:
    struct PenObserver **herep;
  CODE:
    herep = &self->observers;

    while(*herep) {
      struct PenObserver *here = (*herep);

      if(SvRV(observer) != SvRV(here->observer)) {
        herep = &here->next;
        continue;
      }

      *herep = here->next;

      SvREFCNT_dec(here->observer);
      SvREFCNT_dec(here->id);
      Safefree(here);
    }

    if(self->event_id && !self->observers) {
      tickit_pen_unbind_event_id(self->pen, self->event_id);
      self->event_id = 0;
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
get_input_handle(self)
  Tickit::Term  self
  CODE:
    if(self->input_handle)
      RETVAL = newRV_inc(self->input_handle);
    else
      XSRETURN_UNDEF;
  OUTPUT:
    RETVAL

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
get_output_handle(self)
  Tickit::Term  self
  CODE:
    if(self->output_handle)
      RETVAL = newRV_inc(self->output_handle);
    else
      XSRETURN_UNDEF;
  OUTPUT:
    RETVAL

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
flush(self)
  Tickit::Term  self
  CODE:
    tickit_term_flush(self->tt);

void
set_output_buffer(self,len)
  Tickit::Term  self
  size_t        len
  CODE:
    tickit_term_set_output_buffer(self->tt, len);

void
set_utf8(self,utf8)
  Tickit::Term  self
  int           utf8;
  CODE:
    tickit_term_set_utf8(self->tt, utf8);

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
    int        pen_temp = 0;
  CODE:
    if(items == 2 && SvROK(ST(1)) && sv_derived_from(ST(1), "Tickit::Pen")) {
      IV tmp = SvIV((SV*)SvRV(ST(1)));
      Tickit__Pen self = INT2PTR(Tickit__Pen, tmp);
      pen = self->pen;
    }
    else {
      pen = pen_from_args(SP-items+2, items-1);
      pen_temp = 1;
    }
    tickit_term_chpen(self->tt, pen);
    if(pen_temp)
      tickit_pen_destroy(pen);

void
setpen(self,...)
  Tickit::Term  self
  INIT:
    TickitPen *pen;
    int        pen_temp = 0;
  CODE:
    if(items == 2 && SvROK(ST(1)) && sv_derived_from(ST(1), "Tickit::Pen")) {
      IV tmp = SvIV((SV*)SvRV(ST(1)));
      Tickit__Pen self = INT2PTR(Tickit__Pen, tmp);
      pen = self->pen;
    }
    else {
      pen = pen_from_args(SP-items+2, items-1);
      pen_temp = 1;
    }
    tickit_term_setpen(self->tt, pen);
    if(pen_temp)
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
    if(tickit_string_count(s, &pos, &limit) == -1)
      XSRETURN_UNDEF;

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

      if(tickit_string_countmore(s, &pos, &limit) == -1)
        XSRETURN_UNDEF;

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

      if(tickit_string_countmore(s, &pos, &limit) == -1)
        XSRETURN_UNDEF;

      mPUSHu(pos.codepoints);

      if(GIMME_V != G_ARRAY)
        XSRETURN(1);
    }

    XSRETURN(items - 1);
