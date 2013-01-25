#include "termdriver.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef HAVE_UNIBILIUM
# include "unibilium.h"
#else
# include <curses.h>
# include <term.h>

/* term.h has defined 'lines' as a macro. Eugh. We'd really rather prefer it
 * didn't pollute our namespace so we'll provide some functions here and then
 * #undef the name pollution
 */
static inline int terminfo_bce(void)     { return back_color_erase; }
static inline int terminfo_lines(void)   { return lines; }
static inline int terminfo_columns(void) { return columns; }

# undef back_color_erase
# undef lines
# undef columns
#endif


struct XTermDriver {
  TickitTermDriver driver;

  struct {
    unsigned int altscreen:1;
    unsigned int cursorvis:1;
    unsigned int cursorblink:1;
    unsigned int mouse:1;
    unsigned int keypad:1;
  } mode;

  struct {
    unsigned int bce:1;
    unsigned int slrm:1;
  } cap;
};

static void print(TickitTermDriver *ttd, const char *str)
{
  tickit_termdrv_write_str(ttd, str, strlen(str));
}

static void goto_abs(TickitTermDriver *ttd, int line, int col)
{
  if(line != -1 && col > 0)
    tickit_termdrv_write_strf(ttd, "\e[%d;%dH", line+1, col+1);
  else if(line != -1 && col == 0)
    tickit_termdrv_write_strf(ttd, "\e[%dH", line+1);
  else if(line != -1)
    tickit_termdrv_write_strf(ttd, "\e[%dd", line+1);
  else if(col > 0)
    tickit_termdrv_write_strf(ttd, "\e[%dG", col+1);
  else if(col != -1)
    tickit_termdrv_write_str(ttd, "\e[G", 3);
}

static void move_rel(TickitTermDriver *ttd, int downward, int rightward)
{
  if(downward > 1)
    tickit_termdrv_write_strf(ttd, "\e[%dB", downward);
  else if(downward == 1)
    tickit_termdrv_write_str(ttd, "\e[B", 3);
  else if(downward == -1)
    tickit_termdrv_write_str(ttd, "\e[A", 3);
  else if(downward < -1)
    tickit_termdrv_write_strf(ttd, "\e[%dA", -downward);

  if(rightward > 1)
    tickit_termdrv_write_strf(ttd, "\e[%dC", rightward);
  else if(rightward == 1)
    tickit_termdrv_write_str(ttd, "\e[C", 3);
  else if(rightward == -1)
    tickit_termdrv_write_str(ttd, "\e[D", 3);
  else if(rightward < -1)
    tickit_termdrv_write_strf(ttd, "\e[%dD", -rightward);
}

static int scrollrect(TickitTermDriver *ttd, int top, int left, int lines, int cols, int downward, int rightward)
{
  struct XTermDriver *xd = (struct XTermDriver *)ttd;

  if(!downward && !rightward)
    return 1;

  int term_cols;
  tickit_term_get_size(ttd->tt, NULL, &term_cols);

  /* Use DECSLRM only for 1 line of insert/delete, because any more and it's
   * likely better to use the generic system below
   */
  if(((xd->cap.slrm && lines == 1) || (left + cols == term_cols))
      && downward == 0) {
    if(left + cols < term_cols)
      tickit_termdrv_write_strf(ttd, "\e[;%ds", left + cols);

    for(int line = top; line < top + lines; line++) {
      goto_abs(ttd, line, left);
      if(rightward > 1)
        tickit_termdrv_write_strf(ttd, "\e[%d@", rightward);  /* DCH */
      else if(rightward == 1)
        tickit_termdrv_write_str(ttd, "\e[@", 3);             /* DCH1 */
      else if(rightward == -1)
        tickit_termdrv_write_str(ttd, "\e[P", 3);             /* ICH1 */
      else if(rightward < -1)
        tickit_termdrv_write_strf(ttd, "\e[%dP", -rightward); /* ICH */

    if(left + cols < term_cols)
      tickit_termdrv_write_strf(ttd, "\e[s");
    }

    return 1;
  }

  if(xd->cap.slrm ||
     (left == 0 && cols == term_cols && rightward == 0)) {
    tickit_termdrv_write_strf(ttd, "\e[%d;%dr", top + 1, top + lines);

    if(left > 0 || left + cols < term_cols)
      tickit_termdrv_write_strf(ttd, "\e[%d;%ds", left + 1, left + cols);

    goto_abs(ttd, top, left);

    if(downward > 1)
      tickit_termdrv_write_strf(ttd, "\e[%dM", downward);  /* DL */
    else if(downward == 1)
      tickit_termdrv_write_str(ttd, "\e[M", 3);            /* DL1 */
    else if(downward == -1)
      tickit_termdrv_write_str(ttd, "\e[L", 3);            /* IL1 */
    else if(downward < -1)
      tickit_termdrv_write_strf(ttd, "\e[%dL", -downward); /* IL */

    if(rightward > 1)
      tickit_termdrv_write_strf(ttd, "\e[%d'~", rightward);  /* DECDC */
    else if(rightward == 1)
      tickit_termdrv_write_str(ttd, "\e['~", 4);             /* DECDC1 */
    else if(rightward == -1)
      tickit_termdrv_write_str(ttd, "\e['}", 4);             /* DECIC1 */
    if(rightward < -1)
      tickit_termdrv_write_strf(ttd, "\e[%d'}", -rightward); /* DECIC */

    tickit_termdrv_write_str(ttd, "\e[r", 3);

    if(left > 0 || left + cols < term_cols)
      tickit_termdrv_write_str(ttd, "\e[s", 3);

    return 1;
  }

  return 0;
}

static void erasech(TickitTermDriver *ttd, int count, int moveend)
{
  struct XTermDriver *xd = (struct XTermDriver *)ttd;

  if(count < 1)
    return;

  /* Even if the terminal can do bce, only use ECH if we're not in
   * reverse-video mode. Most terminals don't do rv+ECH properly
   */
  if(xd->cap.bce && !tickit_pen_get_bool_attr(tickit_termdrv_current_pen(ttd), TICKIT_PEN_REVERSE)) {
    if(count == 1)
      tickit_termdrv_write_str(ttd, "\e[X", 3);
    else
      tickit_termdrv_write_strf(ttd, "\e[%dX", count);

    if(moveend == 1)
      move_rel(ttd, 0, count);
  }
  else {
     /* TODO: consider tickit_termdrv_write_chrfill(ttd, c, n)
     */
    char *spaces = tickit_termdrv_get_tmpbuffer(ttd, 64);
    memset(spaces, ' ', 64);
    while(count > 64) {
      tickit_termdrv_write_str(ttd, spaces, 64);
      count -= 64;
    }
    tickit_termdrv_write_str(ttd, spaces, count);

    if(moveend == 0)
      move_rel(ttd, 0, -count);
  }
}

/* clear() may collide with something from curses.h or term.h */
static void ttd_clear(TickitTermDriver *ttd)
{
  tickit_termdrv_write_strf(ttd, "\e[2J", 4);
}

static struct SgrOnOff { int on, off; } sgr_onoff[] = {
  { 30, 39 }, /* fg */
  { 40, 49 }, /* bg */
  {  1, 22 }, /* bold */
  {  4, 24 }, /* under */
  {  3, 23 }, /* italic */
  {  7, 27 }, /* reverse */
  {  9, 29 }, /* strike */
  { 10, 10 }, /* altfont */
};

static void chpen(TickitTermDriver *ttd, const TickitPen *delta, const TickitPen *final)
{
  /* There can be at most 12 SGR parameters; 3 from each of 2 colours, and
   * 6 single attributes
   */
  int params[12];
  int pindex = 0;

  for(TickitPenAttr attr = 0; attr < TICKIT_N_PEN_ATTRS; attr++) {
    if(!tickit_pen_has_attr(delta, attr))
      continue;

    struct SgrOnOff *onoff = &sgr_onoff[attr];

    int val;

    switch(attr) {
    case TICKIT_PEN_FG:
    case TICKIT_PEN_BG:
      val = tickit_pen_get_colour_attr(delta, attr);
      if(val < 0)
        params[pindex++] = onoff->off;
      else if(val < 8)
        params[pindex++] = onoff->on + val;
      else if(val < 16)
        params[pindex++] = onoff->on+60 + val-8;
      else {
        params[pindex++] = (onoff->on+8) | 0x80000000;
        params[pindex++] = 5 | 0x80000000;
        params[pindex++] = val;
      }
      break;

    case TICKIT_PEN_ALTFONT:
      val = tickit_pen_get_int_attr(delta, attr);
      if(val < 0 || val >= 10)
        params[pindex++] = onoff->off;
      else
        params[pindex++] = onoff->on + val;
      break;

    case TICKIT_PEN_BOLD:
    case TICKIT_PEN_UNDER:
    case TICKIT_PEN_ITALIC:
    case TICKIT_PEN_REVERSE:
    case TICKIT_PEN_STRIKE:
      val = tickit_pen_get_bool_attr(delta, attr);
      params[pindex++] = val ? onoff->on : onoff->off;
      break;

    case TICKIT_N_PEN_ATTRS:
      break;
    }
  }

  if(pindex == 0)
    return;

  /* If we're going to clear all the attributes then empty SGR is neater */
  if(!tickit_pen_is_nondefault(final))
    pindex = 0;

  /* Render params[] into a CSI string */

  size_t len = 3; /* ESC [ ... m */
  for(int i = 0; i < pindex; i++)
    len += snprintf(NULL, 0, "%d", params[i]&0x7fffffff) + 1;
  if(pindex > 0)
    len--; /* Last one has no final separator */

  char *buffer = tickit_termdrv_get_tmpbuffer(ttd, len + 1);
  char *s = buffer;

  s += sprintf(s, "\e[");
  for(int i = 0; i < pindex-1; i++)
    /* TODO: Work out what terminals support :s */
    s += sprintf(s, "%d%c", params[i]&0x7fffffff, ';');
  if(pindex > 0)
    s += sprintf(s, "%d", params[pindex-1]&0x7fffffff);
  sprintf(s, "m");

  tickit_termdrv_write_str(ttd, buffer, len);
}

static int setctl_int(TickitTermDriver *ttd, TickitTermCtl ctl, int value)
{
  struct XTermDriver *xd = (struct XTermDriver *)ttd;

  switch(ctl) {
    case TICKIT_TERMCTL_ALTSCREEN:
      if(!xd->mode.altscreen == !value)
        return 1;

      tickit_termdrv_write_str(ttd, value ? "\e[?1049h" : "\e[?1049l", 0);
      xd->mode.altscreen = !!value;
      return 1;

    case TICKIT_TERMCTL_CURSORVIS:
      if(!xd->mode.cursorvis == !value)
        return 1;

      tickit_termdrv_write_str(ttd, value ? "\e[?25h" : "\e[?25l", 0);
      xd->mode.cursorvis = !!value;
      return 1;

    case TICKIT_TERMCTL_CURSORBLINK:
      /* We don't actually know whether this was enabled initially, so best
       * just to always apply this
       */
      tickit_termdrv_write_str(ttd, value ? "\e[?12h" : "\e[?12l", 0);
      xd->mode.cursorblink = !!value;
      return 1;

    case TICKIT_TERMCTL_MOUSE:
      if(!xd->mode.mouse == !value)
        return 1;

      tickit_termdrv_write_str(ttd, value ? "\e[?1002h\e[?1006h" : "\e[?1002l\e[?1006l", 0);
      xd->mode.mouse = !!value;
      return 1;

    case TICKIT_TERMCTL_CURSORSHAPE:
      tickit_termdrv_write_strf(ttd, "\e[%d q", value * 2 + (xd->mode.cursorblink ? -1 : 0));
      return 1;

    case TICKIT_TERMCTL_KEYPAD_APP:
      if(!xd->mode.keypad == !value)
        return 1;

      tickit_termdrv_write_strf(ttd, value ? "\e=" : "\e>");
      return 1;

    default:
      return 0;
  }
}

static int setctl_str(TickitTermDriver *ttd, TickitTermCtl ctl, const char *value)
{
  switch(ctl) {
    case TICKIT_TERMCTL_ICON_TEXT:
      tickit_termdrv_write_strf(ttd, "\e]1;%s\e\\", value);
      return 1;

    case TICKIT_TERMCTL_TITLE_TEXT:
      tickit_termdrv_write_strf(ttd, "\e]2;%s\e\\", value);
      return 1;

    case TICKIT_TERMCTL_ICONTITLE_TEXT:
      tickit_termdrv_write_strf(ttd, "\e]0;%s\e\\", value);
      return 1;

    default:
      return 0;
  }
}

static void start(TickitTermDriver *ttd)
{
  // Enable DECSLRM
  tickit_termdrv_write_strf(ttd, "\e[?69h");

  // Find out if DECSLRM is actually supported
  tickit_termdrv_write_strf(ttd, "\e[?69$p");
}

static void gotkey(TickitTermDriver *ttd, TermKey *tk, const TermKeyKey *key)
{
  struct XTermDriver *xd = (struct XTermDriver *)ttd;

  if(key->type == TERMKEY_TYPE_MODEREPORT) {
    int initial, mode, value;
    termkey_interpret_modereport(tk, key, &initial, &mode, &value);

    if(initial == '?') // DEC mode
      switch(mode) {
        case 69: // DECVSSM
          if(value == 1 || value == 2)
            xd->cap.slrm = 1;
          break;
      }
  }
}

static void stop(TickitTermDriver *ttd)
{
  struct XTermDriver *xd = (struct XTermDriver *)ttd;

  if(xd->mode.mouse)
    setctl_int(ttd, TICKIT_TERMCTL_MOUSE, 0);
  if(!xd->mode.cursorvis)
    setctl_int(ttd, TICKIT_TERMCTL_CURSORVIS, 1);
  if(xd->mode.altscreen)
    setctl_int(ttd, TICKIT_TERMCTL_ALTSCREEN, 0);
  if(xd->mode.keypad)
    setctl_int(ttd, TICKIT_TERMCTL_KEYPAD_APP, 0);
}

static void destroy(TickitTermDriver *ttd)
{
  struct XTermDriver *xd = (struct XTermDriver *)ttd;

  free(xd);
}

TickitTermDriverVTable xterm_vtable = {
  .destroy    = destroy,
  .start      = start,
  .stop       = stop,
  .print      = print,
  .goto_abs   = goto_abs,
  .move_rel   = move_rel,
  .scrollrect = scrollrect,
  .erasech    = erasech,
  .clear      = ttd_clear,
  .chpen      = chpen,
  .setctl_int = setctl_int,
  .setctl_str = setctl_str,
  .gotkey     = gotkey,
};

static TickitTermDriver *new(TickitTerm *tt, const char *termtype)
{
  struct XTermDriver *xd = malloc(sizeof(struct XTermDriver));
  xd->driver.vtable = &xterm_vtable;
  xd->driver.tt = tt;

  xd->mode.altscreen = 0;
  xd->mode.cursorvis = 1;
  xd->mode.mouse     = 0;

  xd->cap.bce = 1;

  /* This will be set to 1 later if the terminal responds appropriately to the
   * DECRQM on DECVSSM
   */
  xd->cap.slrm = 0;

#ifdef HAVE_UNIBILIUM
  {
    unibi_term *ut = unibi_from_term(termtype);
    if(ut) {
      xd->cap.bce = unibi_get_bool(ut, unibi_back_color_erase);

      tickit_term_set_size(tt, unibi_get_num(ut, unibi_lines), unibi_get_num(ut, unibi_columns));

      unibi_destroy(ut);
    }
  }
#else
  {
    int err;
    if(setupterm((char*)termtype, 1, &err) == OK) {
      xd->cap.bce = terminfo_bce();

      tickit_term_set_size(tt, terminfo_lines(), terminfo_columns());
    }
  }
#endif

  return (TickitTermDriver*)xd;
}

TickitTermDriverProbe xterm_probe = {
  .new = new,
};