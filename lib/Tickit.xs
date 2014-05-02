/*  You may distribute under the terms of either the GNU General Public License
 *  or the Artistic License (the same terms as Perl itself)
 *
 *  (C) Paul Evans, 2011-2014 -- leonerd@leonerd.org.uk
 */


#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <tickit.h>
#include <tickit-termdrv.h>
#include <tickit-mockterm.h>

#include "linechars.inc"

#define streq(a,b) (strcmp(a,b)==0)

// UVs also have the IOK flag set
#define SvIsNumeric(sv) (SvFLAGS(sv) & (SVp_IOK|SVp_NOK))

static TickitEventType tickit_name2ev(const char *name)
{
  switch(name[0]) {
    case 'c':
      return streq(name+1, "hange") ? TICKIT_EV_CHANGE
                                    : -1;
    case 'k':
      return streq(name+1, "ey") ? TICKIT_EV_KEY
                                 : -1;
    case 'm':
      return streq(name+1, "ouse") ? TICKIT_EV_MOUSE
                                   : -1;
    case 'r':
      return streq(name+1, "esize") ? TICKIT_EV_RESIZE
                                    : -1;
  }
  return -1;
}

static SV *newSVivpv(int iv, const char *pv)
{
  SV *sv = newSViv(iv);
  if(pv) { sv_setpv(sv, pv); SvPOK_on(sv); }
  return sv;
}

static SV *tickit_ev2sv(TickitEventType ev)
{
  const char *name = NULL;
  switch(ev) {
    case TICKIT_EV_CHANGE: name = "change"; break;
    case TICKIT_EV_KEY:    name = "key";    break;
    case TICKIT_EV_MOUSE:  name = "mouse";  break;
    case TICKIT_EV_RESIZE: name = "resize"; break;
  }
  return newSVivpv(ev, name);
}

static SV *tickit_keyevtype2sv(int type)
{
  const char *name = NULL;
  switch(type) {
    case TICKIT_KEYEV_KEY:  name = "key";  break;
    case TICKIT_KEYEV_TEXT: name = "text"; break;
  }
  return newSVivpv(type, name);
}

static SV *tickit_mouseevtype2sv(int type)
{
  const char *name = NULL;
  switch(type) {
    case TICKIT_MOUSEEV_PRESS:   name = "press";   break;
    case TICKIT_MOUSEEV_DRAG:    name = "drag";    break;
    case TICKIT_MOUSEEV_RELEASE: name = "release"; break;
    case TICKIT_MOUSEEV_WHEEL:   name = "wheel";   break;
  }
  return newSVivpv(type, name);
}

static SV *tickit_mouseevbutton2sv(int type, int button)
{
  const char *name = NULL;
  if(type == TICKIT_MOUSEEV_WHEEL)
    switch(button) {
      case TICKIT_MOUSEWHEEL_UP:   name = "up";   break;
      case TICKIT_MOUSEWHEEL_DOWN: name = "down"; break;
    }
  return newSVivpv(button, name);
}

struct GenericEventData
{
  SV *self;
  CV *code;
  SV *data;
};

/***************
 * Tickit::Pen *
 ***************/

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

static SV *newSVpen(TickitPen *pen, char *package)
{
  SV *sv = newSV(0);
  Tickit__Pen self;

  Newx(self, 1, struct Tickit__Pen);
  sv_setref_pv(sv, package ? package : "Tickit::Pen::Immutable", self);
  self->self = newSVsv(sv);
  sv_rvweaken(self->self); // Avoid a cycle

  self->pen = pen;
  self->observers = NULL;

  return sv;
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
    if(!SvPOK(val) && SvIsNumeric(val))
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

    TickitPenAttr attr = tickit_pen_lookup_attr(name);
    if(attr != -1)
      pen_set_attr(pen, attr, value);
  }

  return pen;
}

static void pen_set_attrs(TickitPen *pen, HV *attrs)
{
  TickitPenAttr a;
  for(a = 0; a < TICKIT_N_PEN_ATTRS; a++) {
    const char *name = tickit_pen_attrname(a);
    SV *val = hv_delete(attrs, name, strlen(name), 0);
    if(!val)
      continue;

    if(!SvOK(val))
      tickit_pen_clear_attr(pen, a);
    else
      pen_set_attr(pen, a, val);
  }
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

/****************
 * Tickit::Rect *
 ****************/

typedef TickitRect *Tickit__Rect;

/* Really cheating and treading on Perl's namespace but hopefully it will be OK */
static SV *newSVrect(TickitRect *rect)
{
  TickitRect *self;
  Newx(self, 1, TickitRect);
  *self = *rect;
  return sv_setref_pv(newSV(0), "Tickit::Rect", self);
}
#define mPUSHrect(rect) PUSHs(sv_2mortal(newSVrect(rect)))

/*******************
 * Tickit::RectSet *
 *******************/

typedef TickitRectSet *Tickit__RectSet;

/************************
 * Tickit::RenderBuffer *
 ************************/

typedef TickitRenderBuffer *Tickit__RenderBuffer;

/****************
 * Tickit::Term *
 ****************/

typedef struct Tickit__Term {
  TickitTerm *tt;
  SV         *input_handle;
  SV         *output_handle;
  CV         *output_func;

  SV         *self;
  HV         *event_ids;
} *Tickit__Term;

static TickitTermCtl term_name2ctl(const char *name)
{
  switch(name[0]) {
    case 'a':
      return streq(name+1, "ltscreen") ? TICKIT_TERMCTL_ALTSCREEN
                                       : -1;
    case 'c':
      return streq(name+1, "olors")      ? TICKIT_TERMCTL_COLORS
           : streq(name+1, "ursorblink") ? TICKIT_TERMCTL_CURSORBLINK
           : streq(name+1, "ursorshape") ? TICKIT_TERMCTL_CURSORSHAPE
           : streq(name+1, "ursorvis")   ? TICKIT_TERMCTL_CURSORVIS
                                         : -1;
    case 'i':
      return streq(name+1, "con_text")      ? TICKIT_TERMCTL_ICON_TEXT
           : streq(name+1, "contitle_text") ? TICKIT_TERMCTL_ICONTITLE_TEXT
                                            : -1;
    case 'k':
      return streq(name+1, "eypad_app") ? TICKIT_TERMCTL_KEYPAD_APP
                                        : -1;
    case 'm':
      return streq(name+1, "ouse") ? TICKIT_TERMCTL_MOUSE
                                       : -1;
    case 't':
      return streq(name+1, "itle_text") ? TICKIT_TERMCTL_TITLE_TEXT
                                        : -1;
  }
  return -1;
}

static void term_userevent_fn(TickitTerm *tt, TickitEventType ev, TickitEvent *args, void *user)
{
  struct GenericEventData *data = user;

  if(ev & ~TICKIT_EV_UNBIND) {
    HV *argshash = newHV();

    switch(ev) {
      case TICKIT_EV_KEY:
        hv_store(argshash, "type",   4, tickit_keyevtype2sv(args->type), 0);
        hv_store(argshash, "str",    3, newSVpvn_utf8(args->str, strlen(args->str), 1), 0);
        hv_store(argshash, "mod",    3, newSViv(args->mod), 0);
        break;

      case TICKIT_EV_MOUSE:
        hv_store(argshash, "type",   4, tickit_mouseevtype2sv(args->type), 0);
        hv_store(argshash, "button", 6, tickit_mouseevbutton2sv(args->type, args->button), 0);
        hv_store(argshash, "line",   4, newSViv(args->line),   0);
        hv_store(argshash, "col",    3, newSViv(args->col),    0);
        hv_store(argshash, "mod",    3, newSViv(args->mod), 0);
        break;

      case TICKIT_EV_RESIZE:
        hv_store(argshash, "lines",  5, newSViv(args->lines),  0);
        hv_store(argshash, "cols",   4, newSViv(args->cols),   0);
        break;

      // These don't happen to terminal
      case TICKIT_EV_CHANGE:
        SvREFCNT_dec(argshash);
        return;
    }

    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 4);
    PUSHs(data->self);
    mPUSHs(tickit_ev2sv(ev));
    mPUSHs(newRV_noinc((SV*)argshash));
    mPUSHs(newSVsv(data->data));
    PUTBACK;

    call_sv((SV*)(data->code), G_VOID);

    FREETMPS;
    LEAVE;
  }

  if(ev & TICKIT_EV_UNBIND) {
    SvREFCNT_dec(data->self);
    SvREFCNT_dec(data->code);
    SvREFCNT_dec(data->data);
    Safefree(data);
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

static SV *newSVterm(TickitTerm *tt, char *package)
{
  Tickit__Term self;
  SV *ret;

  Newx(self, 1, struct Tickit__Term);
  ret = newSV(0);
  sv_setref_pv(ret, package, self);
  self->self = newSVsv(ret);
  sv_rvweaken(self->self); // Avoid a cycle

  self->tt = tt;
  self->input_handle  = NULL;
  self->output_handle = NULL;
  self->output_func = NULL;

  self->event_ids = newHV();

  return ret;
}

/*********************
 * Tickit::StringPos *
 *********************/

typedef TickitStringPos *Tickit__StringPos;

static Tickit__StringPos new_stringpos(SV **svp)
{
  TickitStringPos *pos;

  Newx(pos, 1, TickitStringPos);
  *svp = newSV(0);
  sv_setref_pv(*svp, "Tickit::StringPos", pos);

  return pos;
}

static void setup_constants(void)
{
  HV *stash;
  AV *export;

  stash = gv_stashpvn("Tickit::Term", 12, TRUE);
  export = get_av("Tickit::Term::EXPORT_OK", TRUE);

#define DO_CONSTANT(c) \
  newCONSTSUB(stash, #c+7, newSViv(c)); \
  av_push(export, newSVpv(#c+7, 0));

  DO_CONSTANT(TICKIT_TERMCTL_ALTSCREEN)
  DO_CONSTANT(TICKIT_TERMCTL_CURSORVIS)
  DO_CONSTANT(TICKIT_TERMCTL_CURSORBLINK)
  DO_CONSTANT(TICKIT_TERMCTL_CURSORSHAPE)
  DO_CONSTANT(TICKIT_TERMCTL_ICON_TEXT)
  DO_CONSTANT(TICKIT_TERMCTL_ICONTITLE_TEXT)
  DO_CONSTANT(TICKIT_TERMCTL_KEYPAD_APP)
  DO_CONSTANT(TICKIT_TERMCTL_MOUSE)
  DO_CONSTANT(TICKIT_TERMCTL_TITLE_TEXT)
  DO_CONSTANT(TICKIT_TERMCTL_COLORS)

  DO_CONSTANT(TICKIT_TERM_CURSORSHAPE_BLOCK)
  DO_CONSTANT(TICKIT_TERM_CURSORSHAPE_UNDER)
  DO_CONSTANT(TICKIT_TERM_CURSORSHAPE_LEFT_BAR)

  DO_CONSTANT(TICKIT_TERM_MOUSEMODE_OFF)
  DO_CONSTANT(TICKIT_TERM_MOUSEMODE_CLICK)
  DO_CONSTANT(TICKIT_TERM_MOUSEMODE_DRAG)
  DO_CONSTANT(TICKIT_TERM_MOUSEMODE_MOVE)

  DO_CONSTANT(TICKIT_MOD_SHIFT)
  DO_CONSTANT(TICKIT_MOD_ALT)
  DO_CONSTANT(TICKIT_MOD_CTRL)
}

MODULE = Tickit             PACKAGE = Tickit::Pen

SV *
_new(package, attrs)
  char *package
  HV   *attrs
  INIT:
    Tickit__Pen  self;
    TickitPen   *pen;
  CODE:
    pen = tickit_pen_new();
    if(!pen)
      XSRETURN_UNDEF;

    pen_set_attrs(pen, attrs);

    RETVAL = newSVpen(pen, package);
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
    if((a = tickit_pen_lookup_attr(attr)) == -1)
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
    if((a = tickit_pen_lookup_attr(attr)) == -1)
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
      mPUSHs(newSVpv(tickit_pen_attrname(a), 0));
      mPUSHs(pen_get_attr(self->pen, a));
    }
    XSRETURN(count);

bool
equiv_attr(self,other,attr)
  Tickit::Pen  self
  Tickit::Pen  other
  char        *attr
  INIT:
    TickitPenAttr a;
  CODE:
    if((a = tickit_pen_lookup_attr(attr)) == -1)
      XSRETURN_UNDEF;
    RETVAL = tickit_pen_equiv_attr(self->pen, other->pen, a);
  OUTPUT:
    RETVAL

bool
equiv(self,other)
  Tickit::Pen  self
  Tickit::Pen  other
  CODE:
    RETVAL = tickit_pen_equiv(self->pen, other->pen);
  OUTPUT:
    RETVAL

MODULE = Tickit             PACKAGE = Tickit::Pen::Mutable

void
chattr(self,attr,value)
  Tickit::Pen  self
  char        *attr
  SV          *value
  INIT:
    TickitPenAttr a;
  CODE:
    if((a = tickit_pen_lookup_attr(attr)) == -1)
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
  CODE:
    pen_set_attrs(self->pen, attrs);

void
delattr(self,attr)
  Tickit::Pen  self
  char        *attr
  INIT:
    TickitPenAttr a;
  CODE:
    if((a = tickit_pen_lookup_attr(attr)) == -1)
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

MODULE = Tickit             PACKAGE = Tickit::Rect

Tickit::Rect
_new(package,top,left,lines,cols)
  char *package
  int top
  int left
  int lines
  int cols
  CODE:
    Newx(RETVAL, 1, TickitRect);
    tickit_rect_init_sized(RETVAL, top, left, lines, cols);
  OUTPUT:
    RETVAL

void
DESTROY(self)
  Tickit::Rect self
  CODE:
    Safefree(self);

Tickit::Rect
intersect(self,other)
  Tickit::Rect self
  Tickit::Rect other
  INIT:
    TickitRect ret;
  CODE:
    if(!tickit_rect_intersect(&ret, self, other))
      XSRETURN_UNDEF;

    Newx(RETVAL, 1, TickitRect);
    *RETVAL = ret;
  OUTPUT:
    RETVAL

Tickit::Rect
translate(self,downward,rightward)
  Tickit::Rect self
  int          downward
  int          rightward
  CODE:
    Newx(RETVAL, 1, TickitRect);
    tickit_rect_init_sized(RETVAL, self->top + downward, self->left + rightward,
      self->lines, self->cols);
  OUTPUT:
    RETVAL

int
top(self)
  Tickit::Rect self
  CODE:
    RETVAL = self->top;
  OUTPUT:
    RETVAL

int
left(self)
  Tickit::Rect self
  CODE:
    RETVAL = self->left;
  OUTPUT:
    RETVAL

int
lines(self)
  Tickit::Rect self
  CODE:
    RETVAL = self->lines;
  OUTPUT:
    RETVAL

int
cols(self)
  Tickit::Rect self
  CODE:
    RETVAL = self->cols;
  OUTPUT:
    RETVAL

int
bottom(self)
  Tickit::Rect self
  CODE:
    RETVAL = tickit_rect_bottom(self);
  OUTPUT:
    RETVAL

int
right(self)
  Tickit::Rect self
  CODE:
    RETVAL = tickit_rect_right(self);
  OUTPUT:
    RETVAL

bool
equals(self,other,swap=0)
  Tickit::Rect self
  Tickit::Rect other
  int          swap
  CODE:
    RETVAL = (self->top   == other->top) &&
             (self->lines == other->lines) &&
             (self->left  == other->left) &&
             (self->cols  == other->cols);
  OUTPUT:
    RETVAL

bool
intersects(self,other)
  Tickit::Rect self
  Tickit::Rect other
  CODE:
    RETVAL = tickit_rect_intersects(self, other);
  OUTPUT:
    RETVAL

bool
contains(large,small)
  Tickit::Rect large
  Tickit::Rect small
  CODE:
    RETVAL = tickit_rect_contains(large, small);
  OUTPUT:
    RETVAL

void
add(x,y)
  Tickit::Rect x
  Tickit::Rect y
  INIT:
    int n_rects, i;
    TickitRect rects[3];
  PPCODE:
    n_rects = tickit_rect_add(rects, x, y);

    for(i = 0; i < n_rects; i++)
      mPUSHrect(rects + i);

    XSRETURN(n_rects);

void
subtract(self,hole)
  Tickit::Rect self
  Tickit::Rect hole
  INIT:
    int n_rects, i;
    TickitRect rects[4];
  PPCODE:
    n_rects = tickit_rect_subtract(rects, self, hole);

    for(i = 0; i < n_rects; i++)
      mPUSHrect(rects + i);

    XSRETURN(n_rects);

MODULE = Tickit             PACKAGE = Tickit::RectSet

Tickit::RectSet
new(package)
  char *package
  CODE:
    RETVAL = tickit_rectset_new();
  OUTPUT:
    RETVAL

void
DESTROY(self)
  Tickit::RectSet self
  CODE:
    tickit_rectset_destroy(self);

void
clear(self)
  Tickit::RectSet self
  CODE:
    tickit_rectset_clear(self);

void
rects(self)
  Tickit::RectSet self
  INIT:
    int n;
    TickitRect *rects;
    int i;
  PPCODE:
    n = tickit_rectset_rects(self);

    if(GIMME_V != G_ARRAY) {
      mPUSHi(n);
      XSRETURN(1);
    }

    Newx(rects, n, TickitRect);
    tickit_rectset_get_rects(self, rects, n);

    EXTEND(SP, n);
    for(i = 0; i < n; i++) {
      mPUSHrect(rects + i);
    }

    Safefree(rects);

    XSRETURN(n);

void
add(self,rect)
  Tickit::RectSet self
  Tickit::Rect rect
  CODE:
    tickit_rectset_add(self, rect);

void
subtract(self,rect)
  Tickit::RectSet self
  Tickit::Rect rect
  CODE:
    tickit_rectset_subtract(self, rect);

bool
intersects(self,r)
  Tickit::RectSet self
  Tickit::Rect r
  INIT:
    int i;
  CODE:
    RETVAL = tickit_rectset_intersects(self, r);
  OUTPUT:
    RETVAL

bool
contains(self,r)
  Tickit::RectSet self
  Tickit::Rect r
  INIT:
    int i;
  CODE:
    RETVAL = tickit_rectset_contains(self, r);
  OUTPUT:
    RETVAL

MODULE = Tickit             PACKAGE = Tickit::RenderBuffer

Tickit::RenderBuffer
_xs_new(class,lines,cols)
  char *class
  int lines
  int cols
  CODE:
    RETVAL = tickit_renderbuffer_new(lines, cols);
  OUTPUT:
    RETVAL

void
DESTROY(self)
  Tickit::RenderBuffer self
  CODE:
    tickit_renderbuffer_destroy(self);

int
lines(self)
  Tickit::RenderBuffer self
  CODE:
    tickit_renderbuffer_get_size(self, &RETVAL, NULL);
  OUTPUT:
    RETVAL

int
cols(self)
  Tickit::RenderBuffer self
  CODE:
    tickit_renderbuffer_get_size(self, NULL, &RETVAL);
  OUTPUT:
    RETVAL

SV *
line(self)
  Tickit::RenderBuffer self
  INIT:
    TickitRenderBuffer *rb;
  CODE:
    rb = self;
    if(tickit_renderbuffer_has_cursorpos(rb)) {
      int line;
      tickit_renderbuffer_get_cursorpos(rb, &line, NULL);
      RETVAL = newSViv(line);
    }
    else
      RETVAL = &PL_sv_undef;
  OUTPUT:
    RETVAL

SV *
col(self)
  Tickit::RenderBuffer self
  INIT:
    TickitRenderBuffer *rb;
  CODE:
    rb = self;
    if(tickit_renderbuffer_has_cursorpos(rb)) {
      int col;
      tickit_renderbuffer_get_cursorpos(rb, NULL, &col);
      RETVAL = newSViv(col);
    }
    else
      RETVAL = &PL_sv_undef;
  OUTPUT:
    RETVAL

void
translate(self,downward,rightward)
  Tickit::RenderBuffer self
  int downward
  int rightward
  PPCODE:
    tickit_renderbuffer_translate(self, downward, rightward);

void
clip(self,rect)
  Tickit::RenderBuffer self
  Tickit::Rect rect
  CODE:
    tickit_renderbuffer_clip(self, rect);

void
mask(self,rect)
  Tickit::RenderBuffer self
  Tickit::Rect rect
  CODE:
    tickit_renderbuffer_mask(self, rect);

void
goto(self,line,col)
  Tickit::RenderBuffer self
  SV *line
  SV *col
  CODE:
    if(SvIsNumeric(line) && SvIsNumeric(col))
      tickit_renderbuffer_goto(self, SvIV(line), SvIV(col));
    else
      tickit_renderbuffer_ungoto(self);

void
setpen(self,pen)
  Tickit::RenderBuffer self
  Tickit::Pen pen
  CODE:
    tickit_renderbuffer_setpen(self, pen ? pen->pen : NULL);

void
reset(self)
  Tickit::RenderBuffer self
  CODE:
    tickit_renderbuffer_reset(self);

void
clear(self,pen=NULL)
  Tickit::RenderBuffer self
  Tickit::Pen pen
  CODE:
    tickit_renderbuffer_clear(self, pen ? pen->pen : NULL);

void
save(self)
  Tickit::RenderBuffer self
  CODE:
    tickit_renderbuffer_save(self);

void
savepen(self)
  Tickit::RenderBuffer self
  CODE:
    tickit_renderbuffer_savepen(self);

void
restore(self)
  Tickit::RenderBuffer self
  INIT:
    TickitRenderBuffer *rb;
  CODE:
    tickit_renderbuffer_restore(self);

void
_xs_get_cell(self,line,col)
  Tickit::RenderBuffer self
  int line
  int col
  INIT:
    TickitRenderBuffer *rb;
    STRLEN len;
    SV *text;
    TickitRenderBufferLineMask mask;
  PPCODE:
    rb = self;
    if(!tickit_renderbuffer_get_cell_active(rb, line, col)) {
      XPUSHs(&PL_sv_undef);
      XPUSHs(&PL_sv_undef);
      XSRETURN(2);
    }

    len = tickit_renderbuffer_get_cell_text(rb, line, col, NULL, 0);
    text = newSV(len + 1);
    tickit_renderbuffer_get_cell_text(rb, line, col, SvPVX(text), len + 1);
    SvPOK_on(text); SvUTF8_on(text); SvCUR_set(text, len);
    XPUSHs(sv_2mortal(text));

    mPUSHs(newSVpen(tickit_pen_clone(tickit_renderbuffer_get_cell_pen(rb, line, col)), NULL));

    mask = tickit_renderbuffer_get_cell_linemask(rb, line, col);
    if(!mask.north && !mask.south && !mask.east && !mask.west)
      XSRETURN(2);

    mPUSHi(mask.north);
    mPUSHi(mask.south);
    mPUSHi(mask.east);
    mPUSHi(mask.west);
    XSRETURN(6);

void
_xs_get_span(self,line,col)
  Tickit::RenderBuffer self
  int line
  int col
  INIT:
    TickitRenderBuffer *rb;
    int lines, cols;
    struct TickitRenderBufferSpanInfo info = { 0 };
    SV *text;
  PPCODE:
    rb = self;
    tickit_renderbuffer_get_size(rb, &lines, &cols);

    if(line < 0 || line >= lines)
      croak("$line out of range");
    if(col < 0 || col >= cols)
      croak("$col out of range");

    // Request once without any buffers, to get the text length
    if(tickit_renderbuffer_get_span(rb, line, col, &info, NULL, 0) < 0)
      XSRETURN(0);

    mPUSHi(info.n_columns);

    if(!info.is_active) {
      mPUSHs(&PL_sv_undef);
      mPUSHs(&PL_sv_undef);
      XSRETURN(3);
    }

    text = newSV(info.len + 1);
    info.pen  = tickit_pen_new();

    tickit_renderbuffer_get_span(rb, line, col, &info, SvPVX(text), info.len + 1);

    SvPOK_on(text); SvUTF8_on(text); SvCUR_set(text, info.len);

    mPUSHs(text);
    mPUSHs(newSVpen(info.pen, NULL));
    XSRETURN(3);

void
skip_at(self,line,col,len)
  Tickit::RenderBuffer self
  int line
  int col
  int len
  CODE:
    tickit_renderbuffer_skip_at(self, line, col, len);

void
skip(self,len)
  Tickit::RenderBuffer self
  int len
  CODE:
    if(!tickit_renderbuffer_has_cursorpos(self))
      croak("Cannot ->skip without a virtual cursor position");

    tickit_renderbuffer_skip(self, len);

void
skip_to(self,col)
  Tickit::RenderBuffer self
  int col
  CODE:
    if(!tickit_renderbuffer_has_cursorpos(self))
      croak("Cannot ->skip_to without a virtual cursor position");

    tickit_renderbuffer_skip_to(self, col);

int
text_at(self,line,col,text,pen=NULL)
  Tickit::RenderBuffer self
  int line
  int col
  SV *text
  Tickit::Pen pen
  CODE:
    RETVAL = tickit_renderbuffer_text_at(self, line, col, SvPVutf8_nolen(text), pen ? pen->pen : NULL);
  OUTPUT:
    RETVAL

int
text(self,text,pen=NULL)
  Tickit::RenderBuffer self
  SV *text
  Tickit::Pen pen
  CODE:
    if(!tickit_renderbuffer_has_cursorpos(self))
      croak("Cannot ->text without a virtual cursor position");

    RETVAL = tickit_renderbuffer_text(self, SvPVutf8_nolen(text), pen ? pen->pen : NULL);
  OUTPUT:
    RETVAL

void
erase_at(self,line,col,len,pen=NULL)
  Tickit::RenderBuffer self
  int line
  int col
  int len
  Tickit::Pen pen
  CODE:
    tickit_renderbuffer_erase_at(self, line, col, len, pen ? pen->pen : NULL);

void
erase(self,len,pen=NULL)
  Tickit::RenderBuffer self
  int len
  Tickit::Pen pen
  CODE:
    if(!tickit_renderbuffer_has_cursorpos(self))
      croak("Cannot ->erase without a virtual cursor position");

    tickit_renderbuffer_erase(self, len, pen ? pen->pen : NULL);

void
erase_to(self,col,pen=NULL)
  Tickit::RenderBuffer self
  int col
  Tickit::Pen pen
  CODE:
    if(!tickit_renderbuffer_has_cursorpos(self))
      croak("Cannot ->erase_to without a virtual cursor position");

    tickit_renderbuffer_erase_to(self, col, pen ? pen->pen : NULL);

void
eraserect(self,rect,pen=NULL)
  Tickit::RenderBuffer self
  Tickit::Rect rect
  Tickit::Pen pen
  CODE:
    tickit_renderbuffer_eraserect(self, rect, pen ? pen->pen : NULL);

void
char_at(self,line,col,codepoint,pen=NULL)
  Tickit::RenderBuffer self
  int line
  int col
  int codepoint
  Tickit::Pen pen
  CODE:
    tickit_renderbuffer_char_at(self, line, col, codepoint, pen ? pen->pen : NULL);

void
char(self,codepoint,pen=NULL)
  Tickit::RenderBuffer self
  int codepoint
  Tickit::Pen pen
  CODE:
    tickit_renderbuffer_char(self, codepoint, pen ? pen->pen : NULL);

void
hline_at(self,line,startcol,endcol,style,pen=NULL,caps=0)
  Tickit::RenderBuffer self
  int line
  int startcol
  int endcol
  int style
  Tickit::Pen pen
  int caps
  CODE:
    tickit_renderbuffer_hline_at(self, line, startcol, endcol, style,
      pen ? pen->pen : NULL, caps);

void
vline_at(self,startline,endline,col,style,pen=NULL,caps=0)
  Tickit::RenderBuffer self
  int startline
  int endline
  int col
  int style
  Tickit::Pen pen
  int caps
  CODE:
    tickit_renderbuffer_vline_at(self, startline, endline, col, style,
      pen ? pen->pen : NULL, caps);

void
flush_to_term(self,term)
  Tickit::RenderBuffer self
  Tickit::Term term
  CODE:
    tickit_renderbuffer_flush_to_term(self, term->tt);

MODULE = Tickit             PACKAGE = Tickit::StringPos

SV *
zero(package)
  char *package;
  INIT:
    TickitStringPos *pos;
  CODE:
    pos = new_stringpos(&RETVAL);
    tickit_stringpos_zero(pos);
  OUTPUT:
    RETVAL

SV *
limit_bytes(package,bytes)
  char *package;
  size_t bytes;
  INIT:
    TickitStringPos *pos;
  CODE:
    pos = new_stringpos(&RETVAL);
    tickit_stringpos_limit_bytes(pos, bytes);
  OUTPUT:
    RETVAL

SV *
limit_codepoints(package,codepoints)
  char *package;
  int codepoints;
  INIT:
    TickitStringPos *pos;
  CODE:
    pos = new_stringpos(&RETVAL);
    tickit_stringpos_limit_codepoints(pos, codepoints);
  OUTPUT:
    RETVAL

SV *
limit_graphemes(package,graphemes)
  char *package;
  int graphemes;
  INIT:
    TickitStringPos *pos;
  CODE:
    pos = new_stringpos(&RETVAL);
    tickit_stringpos_limit_graphemes(pos, graphemes);
  OUTPUT:
    RETVAL

SV *
limit_columns(package,columns)
  char *package;
  int columns;
  INIT:
    TickitStringPos *pos;
  CODE:
    pos = new_stringpos(&RETVAL);
    tickit_stringpos_limit_columns(pos, columns);
  OUTPUT:
    RETVAL

void
DESTROY(self)
  Tickit::StringPos self
  CODE:
    Safefree(self);

size_t
bytes(self)
  Tickit::StringPos self;
  CODE:
    RETVAL = self->bytes;
  OUTPUT:
    RETVAL

int
codepoints(self)
  Tickit::StringPos self;
  CODE:
    RETVAL = self->codepoints;
  OUTPUT:
    RETVAL

int
graphemes(self)
  Tickit::StringPos self;
  CODE:
    RETVAL = self->graphemes;
  OUTPUT:
    RETVAL

int
columns(self)
  Tickit::StringPos self;
  CODE:
    RETVAL = self->columns;
  OUTPUT:
    RETVAL

MODULE = Tickit             PACKAGE = Tickit::Term

SV *
_new(package,termtype)
  char *package;
  char *termtype;
  INIT:
    Tickit__Term  self;
    TickitTerm   *tt;
  CODE:
    tt = tickit_term_new_for_termtype(termtype);
    if(!tt)
      XSRETURN_UNDEF;

    RETVAL = newSVterm(tt, package);
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

    if(self->event_ids)
      SvREFCNT_dec(self->event_ids);

    SvREFCNT_dec(self->self);

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
await_started(self,timeout)
  Tickit::Term  self
  double        timeout
  INIT:
    struct timeval tv;
  CODE:
    tv.tv_sec = (long)timeout;
    tv.tv_usec = (timeout - tv.tv_sec) * 1E6;
    tickit_term_await_started(self->tt, &tv);

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

int
bind_event(self,ev,code,data = &PL_sv_undef)
  Tickit::Term  self
  char         *ev
  CV           *code
  SV           *data
  INIT:
    TickitEventType ev_e;
    struct GenericEventData *user;
  CODE:
    ev_e = tickit_name2ev(ev);
    if(ev_e == -1)
      croak("Unrecognised event name '%s'", ev);

    Newx(user, 1, struct GenericEventData);
    user->self = SvREFCNT_inc(self->self);
    user->code = (CV*)SvREFCNT_inc(code);
    user->data = newSVsv(data);

    RETVAL = tickit_term_bind_event(self->tt, ev_e|TICKIT_EV_UNBIND, term_userevent_fn, user);
  OUTPUT:
    RETVAL

void
unbind_event_id(self,id)
  Tickit::Term  self
  int           id
  CODE:
    tickit_term_unbind_event_id(self->tt, id);

SV *
_event_ids(self)
  Tickit::Term  self
  CODE:
    RETVAL = newRV_inc((SV*)self->event_ids);
  OUTPUT:
    RETVAL

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
input_wait(self,timeout=&PL_sv_undef)
  Tickit::Term  self
  SV           *timeout
  CODE:
    if(SvIsNumeric(timeout)) {
      struct timeval tv;
      tv.tv_sec = (long)SvNV(timeout);
      tv.tv_usec = 1E6 * (SvNV(timeout) - tv.tv_sec);
      tickit_term_input_wait(self->tt, &tv);
    }
    else
      tickit_term_input_wait(self->tt, NULL);


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

bool
goto(self,line,col)
  Tickit::Term  self
  SV           *line
  SV           *col
  CODE:
    RETVAL = tickit_term_goto(self->tt, SvOK(line) ? SvIV(line) : -1, SvOK(col) ? SvIV(col) : -1);
  OUTPUT:
    RETVAL

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
  OUTPUT:
    RETVAL

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
print(self,text,pen=NULL)
  Tickit::Term  self
  SV           *text
  Tickit::Pen   pen
  INIT:
    char  *utf8;
    STRLEN len;
  CODE:
    if(pen)
      tickit_term_setpen(self->tt, pen->pen);
    utf8 = SvPVutf8(text, len);
    tickit_term_printn(self->tt, utf8, len);

void
clear(self,pen=NULL)
  Tickit::Term  self
  Tickit::Pen   pen
  CODE:
    if(pen)
      tickit_term_setpen(self->tt, pen->pen);
    tickit_term_clear(self->tt);

void
erasech(self,count,moveend,pen=NULL)
  Tickit::Term  self
  int           count
  SV           *moveend
  Tickit::Pen   pen
  CODE:
    if(pen)
      tickit_term_setpen(self->tt, pen->pen);
    tickit_term_erasech(self->tt, count, SvOK(moveend) ? SvIV(moveend) : -1);

int
getctl_int(self,ctl)
  Tickit::Term self
  SV          *ctl
  INIT:
    TickitTermCtl ctl_e;
  CODE:
    if(SvPOK(ctl)) {
      ctl_e = term_name2ctl(SvPV_nolen(ctl));
      if(ctl_e == -1)
        croak("Unrecognised 'ctl' name '%s'", SvPV_nolen(ctl));
    }
    else if(SvIOK(ctl))
      ctl_e = SvIV(ctl);
    else
      croak("Expected 'ctl' to be an integer or string");

    if(!tickit_term_getctl_int(self->tt, ctl_e, &RETVAL))
      XSRETURN_UNDEF;
  OUTPUT:
    RETVAL

void
setctl_int(self,ctl,value)
  Tickit::Term self
  SV          *ctl
  int          value
  INIT:
    TickitTermCtl ctl_e;
  PPCODE:
    if(SvPOK(ctl)) {
      ctl_e = term_name2ctl(SvPV_nolen(ctl));
      if(ctl_e == -1)
        croak("Unrecognised 'ctl' name '%s'", SvPV_nolen(ctl));
    }
    else if(SvIOK(ctl))
      ctl_e = SvIV(ctl);
    else
      croak("Expected 'ctl' to be an integer or string");

    if(tickit_term_setctl_int(self->tt, ctl_e, value))
      XSRETURN_YES;
    else
      XSRETURN_NO;

int
setctl_str(self,ctl,value)
  Tickit::Term self
  SV          *ctl
  char        *value
  INIT:
    TickitTermCtl ctl_e;
  CODE:
    if(SvPOK(ctl)) {
      ctl_e = term_name2ctl(SvPV_nolen(ctl));
      if(ctl_e == -1)
        croak("Unrecognised 'ctl' name '%s'", SvPV_nolen(ctl));
    }
    else if(SvIOK(ctl))
      ctl_e = SvIV(ctl);
    else
      croak("Expected 'ctl' to be an integer or string");
    RETVAL = tickit_term_setctl_str(self->tt, ctl_e, value);
  OUTPUT:
    RETVAL

MODULE = Tickit::Test::MockTerm    PACKAGE = Tickit::Test::MockTerm

SV *
_new_mocking(package,lines,cols)
  char *package
  int   lines
  int   cols
  INIT:
    TickitMockTerm *mt;
  CODE:
    mt = tickit_mockterm_new(lines, cols);
    if(!mt)
      XSRETURN_UNDEF;

    RETVAL = newSVterm((TickitTerm *)mt, "Tickit::Test::MockTerm");
  OUTPUT:
    RETVAL

void
get_methodlog(self)
  Tickit::Term self
  INIT:
    TickitMockTerm *mt;
    int loglen;
    int i;
  PPCODE:
    mt = (TickitMockTerm *)self->tt;

    EXTEND(SP, (loglen = tickit_mockterm_loglen(mt)));
    for(i = 0; i < loglen; i++) {
      TickitMockTermLogEntry *entry = tickit_mockterm_peeklog(mt, i);
      AV *ret = newAV();
      switch(entry->type) {
      case LOG_GOTO:
        av_push(ret, newSVpv("goto", 0));
        av_push(ret, newSViv(entry->val1)); // line
        av_push(ret, newSViv(entry->val2)); // col
        break;
      case LOG_PRINT:
        av_push(ret, newSVpv("print", 0));
        av_push(ret, newSVpvn_utf8(entry->str, entry->val1, 1));
        break;
      case LOG_ERASECH:
        av_push(ret, newSVpv("erasech", 0));
        av_push(ret, newSViv(entry->val1)); // count
        av_push(ret, newSViv(entry->val2 == 1 ? 1 : 0)); // moveend
        break;
      case LOG_CLEAR:
        av_push(ret, newSVpv("clear", 0));
        break;
      case LOG_SCROLLRECT:
        av_push(ret, newSVpv("scrollrect", 0));
        av_push(ret, newSViv(entry->rect.top));
        av_push(ret, newSViv(entry->rect.left));
        av_push(ret, newSViv(entry->rect.lines));
        av_push(ret, newSViv(entry->rect.cols));
        av_push(ret, newSViv(entry->val1)); // downward
        av_push(ret, newSViv(entry->val2)); // rightward
        break;
      case LOG_SETPEN:
        {
          HV *penattrs = newHV();
          TickitPenAttr attr;

          for(attr = 0; attr < TICKIT_N_PEN_ATTRS; attr++) {
            const char *attrname = tickit_pen_attrname(attr);
            int value;
            if(!tickit_pen_nondefault_attr(entry->pen, attr))
              continue;

            switch(tickit_pen_attrtype(attr)) {
            case TICKIT_PENTYPE_BOOL:
              value = tickit_pen_get_bool_attr(entry->pen, attr); break;
            case TICKIT_PENTYPE_INT:
              value = tickit_pen_get_int_attr(entry->pen, attr); break;
            case TICKIT_PENTYPE_COLOUR:
              value = tickit_pen_get_colour_attr(entry->pen, attr); break;
            }

            sv_setiv(*hv_fetch(penattrs, attrname, strlen(attrname), 1), value);
          }

          av_push(ret, newSVpv("setpen", 0));
          av_push(ret, newRV_noinc((SV *)penattrs));
        }
        break;
      }
      mPUSHs(newRV_noinc((SV *)ret));
    }

    tickit_mockterm_clearlog(mt);

    XSRETURN(i);

SV *
get_display_text(self,line,col,width)
  Tickit::Term self
  int line
  int col
  int width
  INIT:
    STRLEN len;
  CODE:
    len = tickit_mockterm_get_display_text((TickitMockTerm *)self->tt, NULL, 0, line, col, width);

    RETVAL = newSV(len+1);

    tickit_mockterm_get_display_text((TickitMockTerm *)self->tt, SvPVX(RETVAL), len, line, col, width);

    SvPOK_on(RETVAL);
    SvUTF8_on(RETVAL);
    SvCUR_set(RETVAL, len);
  OUTPUT:
    RETVAL

SV *
get_display_pen(self,line,col)
  Tickit::Term self
  int line
  int col
  INIT:
    TickitPen *pen;
    HV *penattrs;
    TickitPenAttr attr;
  CODE:
    pen = tickit_mockterm_get_display_pen((TickitMockTerm *)self->tt, line, col);

    penattrs = newHV();
    for(attr = 0; attr < TICKIT_N_PEN_ATTRS; attr++) {
      const char *attrname;
      if(!tickit_pen_nondefault_attr(pen, attr))
        continue;

      attrname = tickit_pen_attrname(attr);
      hv_store(penattrs, attrname, strlen(attrname), pen_get_attr(pen, attr), 0);
    }

    RETVAL = newRV_noinc((SV *)penattrs);
  OUTPUT:
    RETVAL

void
resize(self,newlines,newcols)
  Tickit::Term self
  int newlines
  int newcols
  CODE:
    tickit_mockterm_resize((TickitMockTerm *)self->tt, newlines, newcols);

int
line(self)
  Tickit::Term self
  ALIAS:
    line        = 0
    col         = 1
    cursorvis   = 2
    cursorshape = 3
  INIT:
    TickitMockTerm *mt;
  CODE:
    mt = (TickitMockTerm *)self->tt;
    switch(ix) {
      case 0: tickit_mockterm_get_position(mt, &RETVAL, NULL); break;
      case 1: tickit_mockterm_get_position(mt, NULL, &RETVAL); break;
      case 2: tickit_term_getctl_int(self->tt, TICKIT_TERMCTL_CURSORVIS, &RETVAL); break;
      case 3: tickit_term_getctl_int(self->tt, TICKIT_TERMCTL_CURSORSHAPE, &RETVAL); break;
    }
  OUTPUT:
    RETVAL

MODULE = Tickit             PACKAGE = Tickit::Utils

size_t
string_count(str,pos,limit=NULL)
    SV *str
    Tickit::StringPos pos
    Tickit::StringPos limit
  INIT:
    char *s;
    STRLEN len;
  CODE:
    if(!SvUTF8(str)) {
      str = sv_mortalcopy(str);
      sv_utf8_upgrade(str);
    }

    s = SvPVutf8(str, len);
    RETVAL = tickit_string_ncount(s, len, pos, limit);
    if(RETVAL == -1)
      XSRETURN_UNDEF;
  OUTPUT:
    RETVAL

size_t
string_countmore(str,pos,limit=NULL)
    SV *str
    Tickit::StringPos pos
    Tickit::StringPos limit
  INIT:
    char *s;
    STRLEN len;
  CODE:
    if(!SvUTF8(str)) {
      str = sv_mortalcopy(str);
      sv_utf8_upgrade(str);
    }

    s = SvPVutf8(str, len);
    RETVAL = tickit_string_ncountmore(s, len, pos, limit);
    if(RETVAL == -1)
      XSRETURN_UNDEF;
  OUTPUT:
    RETVAL

int textwidth(str)
    SV *str
  INIT:
    STRLEN len;
    const char *s;
    TickitStringPos pos, limit = INIT_TICKIT_STRINGPOS_LIMIT_NONE;

  CODE:
    RETVAL = 0;

    if(!SvUTF8(str)) {
      str = sv_mortalcopy(str);
      sv_utf8_upgrade(str);
    }

    s = SvPVutf8(str, len);
    if(tickit_string_ncount(s, len, &pos, &limit) == -1)
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
    size_t bytes;

  PPCODE:
    if(!SvUTF8(str)) {
      str = sv_mortalcopy(str);
      sv_utf8_upgrade(str);
    }

    s = SvPVutf8(str, len);

    EXTEND(SP, items - 1);

    tickit_stringpos_zero(&pos);
    tickit_stringpos_limit_bytes(&limit, len);

    for(i = 1; i < items; i++ ) {
      limit.codepoints = SvUV(ST(i));
      if(limit.codepoints < pos.codepoints)
        croak("chars2cols requires a monotonically-increasing list of character numbers; %d is not greater than %d\n",
          limit.codepoints, pos.codepoints);

      bytes = tickit_string_ncountmore(s, len, &pos, &limit);
      if(bytes == -1)
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
    size_t bytes;

  PPCODE:
    if(!SvUTF8(str)) {
      str = sv_mortalcopy(str);
      sv_utf8_upgrade(str);
    }

    s = SvPVutf8(str, len);

    EXTEND(SP, items - 1);

    tickit_stringpos_zero(&pos);
    tickit_stringpos_limit_bytes(&limit, len);

    for(i = 1; i < items; i++ ) {
      limit.columns = SvUV(ST(i));
      if(limit.columns < pos.columns)
        croak("cols2chars requires a monotonically-increasing list of column numbers; %d is not greater than %d\n",
          limit.columns, pos.columns);

      bytes = tickit_string_ncountmore(s, len, &pos, &limit);
      if(bytes == -1)
        XSRETURN_UNDEF;

      mPUSHu(pos.codepoints);

      if(GIMME_V != G_ARRAY)
        XSRETURN(1);
    }

    XSRETURN(items - 1);

MODULE = Tickit  PACKAGE = Tickit

BOOT:
  setup_constants();
