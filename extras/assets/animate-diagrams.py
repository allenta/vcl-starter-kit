#!/usr/bin/env python3
#
# ############################################################################
# #                                                                          #
# #  DISCLAIMER: THIS FILE IS 100% AI-GENERATED AND HAS NOT BEEN REVIEWED.   #
# #                                                                          #
# #  Everything here was written by an AI assistant: the code, the geometry  #
# #  constants, the arc-length waypoints, the animation timings and the      #
# #  comments. None of it has been reviewed by a human. The same applies to  #
# #  the animated SVG files this script produces, and to the CSS animation   #
# #  overlay embedded in them.                                               #
# #                                                                          #
# #  Do not assume any of it is correct. In particular, the hard-coded       #
# #  coordinates and curve waypoints were derived by machine from the        #
# #  Excalidraw exports, and are only as good as that derivation. Verify     #
# #  before relying on this, and review it before treating it as             #
# #  maintainable project code.                                              #
# #                                                                          #
# ############################################################################

"""Add a CSS animation overlay to the Excalidraw replication diagrams.

Excalidraw cannot export animation, so the animated diagrams used in
README.md are derived artifacts: export each static SVG from
'diagrams.excalidraw' as '<name>-static.svg', then run this script to
produce the animated '<name>.svg' that README.md actually links:

    ./animate-diagrams.py

Both loops follow one cache miss from start to finish, and share a visual
vocabulary: a hollow ring is a request or a notification (it carries no
payload), a filled disc is the object itself in flight, and the green
object is already cached at t=0 while the orange one propagates.

VHA ('replication-vha-static.svg' -> 'replication-vha.svg'):

  1. A GET for the orange object reaches Varnish3, which misses and
     fetches it from the origin.
  2. Varnish3 caches the object, answers the client, and broadcasts a
     notification saying the object is available.
  3. Varnish1 & Varnish2 receive it, fetch the object straight from
     Varnish3, and cache it: full replication.

  Three distinct channels keep those steps apart. Client and origin
  traffic rides the drawn annotation curve; the notification is a wave
  radiating from Varnish3, so it cannot be misread as travelling along
  the drawn 'VHA' arrows; and the peer fetches fly along their own arcs,
  bowed clear of the node row, so Varnish1 pulls directly from Varnish3
  instead of appearing to relay through Varnish2.

Varnish Cluster ('replication-cluster-static.svg' -> 'replication-cluster.svg'):

  1. Nothing is cached yet. A GET for the orange object reaches Varnish3.
  2. Varnish3 is not the node that owns the object, so it self-routes the
     request to Varnish2, which misses and goes to the origin.
  3. The response lands on Varnish2, which caches it and hands it back to
     Varnish3, which also caches it and answers the client.

  Here every leg rides the drawn annotation curve, because that curve
  already traces the whole self-routing round trip.

Everything injected here is opacity-gated, so a renderer without CSS
animation support (and anybody browsing with 'prefers-reduced-motion')
falls back to exactly the static diagram.

Coordinates are tied to the geometry of the current exports. If boxes
move in Excalidraw the assertions below fail loudly rather than silently
misplacing packets, and the constants here need recomputing. Waypoints
are percentages of a curve's arc length, so they must be recomputed too.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

FADE = 0.15               # opacity ramp in/out for every packet
TRAIL_STEP = 0.085        # lag between a packet and each of its trail ghosts
OBJECT_FILL = '#fab005'   # matches the drawn orange object
SIGNAL = '#1971c2'        # matches the drawn cluster boundary
INK = '#1e1e1e'

# Easing carries meaning: a hop to a neighbouring node snaps and settles,
# while the long haul to the origin grinds along at a constant rate.
EASE_EDGE = 'ease-in-out'
EASE_LOCAL = 'cubic-bezier(0.4, 0, 0.2, 1)'
EASE_HAUL = 'linear'

# Every class that is animated, and therefore hidden when animation is off.
ANIMATED = ('.vk-pkt, .vk-wave, .vk-glow, .vk-cap, .vk-track, .vk-bar, '
            '.vk-legend')

# The Excalifont face embedded by Excalidraw is subsetted down to just the
# glyphs the diagram itself uses (32 of them: no 'b', 'd', 'f', 'k', 'm', 'y',
# no capital M/I/S, no punctuation), so captions cannot be set in it without
# silently falling back to a browser default. They are therefore styled as a
# deliberate annotation layer instead of a failed handwriting match.
CAPTION = {'x': 24, 'y': 167, 'size': 13.5, 'fill': '#5c5c5c',
           'font': 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace'}
BLOB_CENTRE = (17.2, 16.8)  # the rotate() centre of every drawn object blob
LEGEND_ALPHA = 0.45         # strength of the legend highlighter swipe


# ---------------------------------------------------------------------------
# Keyframe helpers. Every timeline is expressed in seconds and converted
# here, so beats can be retimed by editing only the timeline constants.
# ---------------------------------------------------------------------------

def pct(loop, t):
    return '%.3f%%' % (100.0 * t / loop)


def kf(loop, name, span, prop, frm, to, opacity=1.0):
    """Animate one property between two values, gated by opacity."""
    t0, t1 = span
    return '''  @keyframes %s {
    0%%, %s   { %s: %s; opacity: 0; }
    %s        { %s: %s; opacity: %s; }
    %s        { %s: %s; opacity: %s; }
    %s, 100%% { %s: %s; opacity: 0; }
  }
''' % (name, pct(loop, t0), prop, frm,
       pct(loop, t0 + FADE), prop, frm, opacity,
       pct(loop, t1), prop, to, opacity,
       pct(loop, t1 + FADE), prop, to)


def kf_hold(loop, name, span, opacity=1.0):
    """Hold an element visible for a span."""
    t0, t1 = span
    return '''  @keyframes %s {
    0%%, %s   { opacity: 0; }
    %s, %s    { opacity: %s; }
    %s, 100%% { opacity: 0; }
  }
''' % (name, pct(loop, t0), pct(loop, t0 + FADE), pct(loop, t1), opacity,
       pct(loop, t1 + FADE))


def kf_stored(loop, name, at, hold, translate):
    """Fade a cached object in with a spring, then out as the loop resets.

    The drawn object carries its position as a 'transform' attribute, which a
    CSS transform would replace outright, so the original translate is baked
    back into every keyframe. Nothing sets 'transform' outside the keyframes,
    which is what keeps the animation-off fallback pixel-identical.
    """
    tx, ty = translate.split()
    cx, cy = BLOB_CENTRE

    def at_scale(s):
        return ('translate(%spx, %spx) translate(%spx, %spx) scale(%s) '
                'translate(-%spx, -%spx)' % (tx, ty, cx, cy, s, cx, cy))

    return '''  @keyframes %s {
    0%%, %s   { opacity: 0; transform: %s; }
    %s        { opacity: 1; transform: %s; }
    %s        { opacity: 1; transform: %s; }
    %s, %s    { opacity: 1; transform: %s; }
    %s, 100%% { opacity: 0; transform: %s; }
  }
''' % (name, pct(loop, at), at_scale(0.35),
       pct(loop, at + 0.13), at_scale(1.22),
       pct(loop, at + 0.26), at_scale(0.95),
       pct(loop, at + 0.36), pct(loop, hold), at_scale(1),
       pct(loop, loop - 0.2), at_scale(1))


def leg(loop, name, span, frm, to):
    """A packet travelling between two waypoints on a curve."""
    return kf(loop, name, span, 'offset-distance', '%s%%' % frm, '%s%%' % to)


def ring(cls, stroke, r=5.5):
    """A request or a notification: hollow, because it carries no payload."""
    return ('  <circle class="vk-pkt %s" r="%s" fill="#ffffff" stroke="%s" '
            'stroke-width="2.5"/>\n' % (cls, r, stroke))


def disc(cls, r=6.5, trail=2):
    """The object itself in flight, with a short comet tail behind it.

    The ghosts share the head's keyframes and simply run late, so they trace
    exactly where it has just been. No extra timeline to keep in sync.
    """
    out = []
    for i in range(trail, 0, -1):
        out.append('  <circle class="vk-pkt %s" r="%.2f" fill="%s" '
                   'fill-opacity="%.2f" style="animation-delay: %.3fs"/>\n'
                   % (cls, r * (1 - 0.16 * i), OBJECT_FILL, 0.40 / i,
                      TRAIL_STEP * i))
    out.append('  <circle class="vk-pkt %s" r="%s" fill="%s" stroke="%s" '
               'stroke-width="1.5"/>\n' % (cls, r, OBJECT_FILL, INK))
    return ''.join(out)


def captions_css(loop, captions):
    """Keyframes for the running commentary. One caption visible at a time."""
    spans = sorted((c[0], c[1]) for c in captions)
    for (_, end), (nxt, _) in zip(spans, spans[1:]):
        if nxt < end:
            sys.exit('captions overlap at %ss; they must run one at a time.' % nxt)
    if spans[-1][1] > loop:
        sys.exit('caption at %ss runs past the end of the loop.' % spans[-1][1])
    css = [names_css(['vk-cap-%d' % i for i in range(len(captions))])]
    for i, (t0, t1, _) in enumerate(captions):
        css.append(kf_hold(loop, 'vk-cap-%d' % i, (t0, t1)))
    return ''.join(css)


def captions_svg(captions):
    out = []
    for i, (_, _, text) in enumerate(captions):
        out.append('  <text class="vk-cap vk-cap-%d" x="%s" y="%s" '
                   'font-family="%s" font-size="%spx" fill="%s" '
                   'text-anchor="start" letter-spacing="0.2" '
                   'style="white-space: pre;">%s</text>\n'
                   % (i, CAPTION['x'], CAPTION['y'], CAPTION['font'],
                      CAPTION['size'], CAPTION['fill'],
                      text.replace('&', '&amp;')))
    return ''.join(out)


def legend_css(loop, span, hold, box):
    """A highlighter swipe across the legend line the loop just demonstrated.

    Box coordinates come from measuring the drawn text's bounding box, so the
    swipe tracks the glyphs rather than a guessed rectangle.
    """
    x, y, w, h = box
    t0, t1 = span
    return '''  .vk-legend {
    animation-name: vk-legend; animation-timing-function: ease-out;
    transform-origin: %spx %spx; mix-blend-mode: multiply;
  }
  @keyframes vk-legend {
    0%%, %s   { opacity: 0; transform: scaleX(0); }
    %s        { opacity: %s; transform: scaleX(0); }
    %s, %s    { opacity: %s; transform: scaleX(1); }
    %s, 100%% { opacity: 0; transform: scaleX(1); }
  }
''' % (x, y + h / 2,
       pct(loop, t0), pct(loop, t0 + 0.05), LEGEND_ALPHA,
       pct(loop, t1), pct(loop, hold), LEGEND_ALPHA,
       pct(loop, loop - 0.2))


def legend_svg(box):
    x, y, w, h = box
    return ('  <rect class="vk-legend" x="%s" y="%s" width="%s" height="%s" '
            'rx="3" fill="%s"/>\n' % (x, y, w, h, OBJECT_FILL))


def progress_css(loop, y):
    """A hairline showing where in the loop you are: it is a loop, not a clip."""
    return '''  .vk-track { animation-name: vk-track; animation-timing-function: linear; }
  .vk-bar { animation-name: vk-bar; animation-timing-function: linear;
            transform-origin: 10px %spx; }
  @keyframes vk-track { 0%%, 100%% { opacity: 0.25; } }
  @keyframes vk-bar {
    0%%   { opacity: 0.75; transform: scaleX(0); }
    100%% { opacity: 0.75; transform: scaleX(1); }
  }
''' % y


def extend_canvas(svg, height, pad):
    """Grow the canvas downwards, giving the progress hairline breathing room.

    The drawn diagram is untouched; this only adds empty space below it, so
    the hairline sits in that strip instead of crowding the origin's cached
    objects. Both the <svg> element and the white background <rect> carry the
    height, and the viewBox has to grow with them.
    """
    grown = height + pad
    tall = ' height="%s"' % height
    if svg.count(tall) != 2:  # the <svg> element and the background <rect>
        sys.exit('expected 2 height="%s" attributes, found %d.'
                 % (height, svg.count(tall)))
    svg = svg.replace(tall, ' height="%s"' % grown)

    box = 'viewBox="0 0 %s %s"'
    vb = re.search(r'viewBox="0 0 ([\d.]+) %s"' % re.escape(str(height)), svg)
    if not vb:
        sys.exit('could not find a viewBox of height %s.' % height)
    return svg.replace(vb.group(0), box % (vb.group(1), grown))


def progress_svg(y, x2):
    return ('  <line class="vk-track" x1="10" y1="%s" x2="%s" y2="%s" '
            'stroke="%s" stroke-width="2" stroke-linecap="round"/>\n'
            '  <line class="vk-bar" x1="10" y1="%s" x2="%s" y2="%s" '
            'stroke="%s" stroke-width="2.5" stroke-linecap="round"/>\n'
            % (y, x2, y, INK, y, x2, y, '#f08c00'))


def preamble(loop):
    return '''  /* VCLSKi: animation overlay generated by animate-diagrams.py.
     Do not hand-edit; regenerate instead. Every animated element is
     hidden by default and only revealed inside a keyframe, so renderers
     without CSS animation support fall back to the static diagram. */
  %s {
    opacity: 0;
    animation-duration: %ss;
    animation-iteration-count: infinite;
  }
  .vk-pkt { animation-timing-function: %s; }
  .vk-cap { animation-timing-function: ease-in-out; }
  .vk-obj { animation-timing-function: ease-out; }
''' % (ANIMATED, loop, EASE_EDGE)


def names_css(names):
    return ''.join('  .%s { animation-name: %s; }\n' % (n, n) for n in names)


def easing_css(pairs):
    return ''.join('  .%s { animation-timing-function: %s; }\n' % (n, e)
                   for n, e in pairs)


REDUCED_MOTION = '''
  @media (prefers-reduced-motion: reduce) {
    %s { display: none; }
    .vk-obj { animation: none; opacity: 1; }
  }
</style>
''' % ANIMATED


# ===========================================================================
# VHA
# ===========================================================================

VHA_CURVE = ('M-0.95 -0.32 C5.69 7.77, 31.92 25.41, 39.98 47.57 C48.05 69.73, '
             '13.46 109.77, 47.44 132.64 C81.43 155.5, 202.65 166.85, 243.91 '
             '184.75 C285.17 202.64, 290.15 220.23, 295.01 239.99 C299.87 '
             '259.75, 298.65 288.05, 273.07 303.31 C247.49 318.56, 176.7 '
             '323.54, 141.53 331.53 C106.36 339.52, 83.03 338.92, 62.03 351.23 '
             'C41.03 363.54, 23.42 396.09, 15.52 405.39')
VHA_CURVE_GROUP = 'translate(342.5999755859375 36.899909973144304)'

# Waypoints along that curve, as a percentage of its arc length.
VHA_START, VHA_CLIENT, VHA_V3, VHA_ORIGIN = 0.0, 13.0, 54.7, 100.0

# Flight paths for the peer fetches, each running from the peer to Varnish3.
# They bow below the node row, through the empty band inside the cluster box,
# so neither one follows a drawn 'VHA' arrow. Undrawn: only packets move.
VHA_FLIGHT_V2 = 'M 390 301 Q 474 335 558 301'
VHA_FLIGHT_V1 = 'M 135 301 C 210 364, 480 364, 558 301'

# The broadcast wave radiates from the centre of Varnish3, clipped to the
# cluster box so it reads as a wave sweeping the cluster.
VHA_V3_CENTRE = (601.2, 275.9)
VHA_WAVE_R = 30
VHA_WAVE_SCALE = 18.7
VHA_CLUSTER_BOX = (10, 200.10471772691199, 676.8, 156.8)

VHA_PEER_BOXES = {'v2': (296.6, 251.5, 100.4, 48.8),
                  'v1': (41.6, 252.3, 100.4, 48.8)}
VHA_GLOW_INSET = -3.0

VHA_OBJECTS = {
    '570.2000122070312 307.7046475364823': 'vk-store-v3',   # from the origin
    '315.79986572265625 308.9047512962479': 'vk-store-v2',  # pulled
    '60.800048828125 307.70470857163855': 'vk-store-v1',    # pulled
}

VHA_LOOP = 12.5
VHA_GET = (0.4, 2.0)      # Client -> Varnish3 (request, no payload yet)
VHA_MISS = (2.3, 3.9)     # Varnish3 -> Origin
VHA_FILL = (4.2, 5.8)     # Origin -> Varnish3 (carrying the object)
VHA_DELIVER = (6.0, 7.2)  # Varnish3 -> Client
VHA_STORE_V3 = 5.8
VHA_WAVES = ((6.0, 7.3), (6.25, 7.55), (6.5, 7.8))
VHA_GLOW_V2 = (6.7, 7.3)  # the nearer peer lights up first
VHA_GLOW_V1 = (7.3, 7.9)
VHA_PULL_V2 = (7.9, 8.6)  # peers request the object straight from Varnish3
VHA_PULL_V1 = (8.1, 9.0)
VHA_GIVE_V2 = (8.8, 9.5)  # ...and it flies back to them
VHA_GIVE_V1 = (9.2, 10.1)
VHA_STORE_V2 = 9.5
VHA_STORE_V1 = 10.1
VHA_HOLD = 11.6
VHA_CANVAS_H = 550.0860848563734  # height of the Excalidraw export
VHA_CANVAS_PAD = 16               # empty strip added below it
VHA_PROGRESS_Y = VHA_CANVAS_H + VHA_CANVAS_PAD / 2
VHA_WIDTH = 686.8

# The legend line the loop demonstrates. Measured from the drawn text's
# bounding box (x=471.04, width=164.58) and padded 5px each side so the swipe
# overhangs the glyphs like a marker pen. The band runs from cap height to a
# little below the baseline. Beware: measure with the font actually loaded
# ('document.fonts.ready'), or Excalifont's metrics come out ~20px narrow.
VHA_LEGEND = (466.04, 385.31, 174.58, 19.5)   # "Full replication"
VHA_LEGEND_SWIPE = (10.3, 10.65)

# Running commentary, one caption at a time. Kept short: these sit in the
# empty band between the Client box and the cluster box.
VHA_CAPTIONS = (
    (0.4, 2.0, 'GET: client asks Varnish3'),
    (2.0, 2.6, 'MISS on Varnish3'),
    (2.6, 4.2, 'Fetching from the origin'),
    (4.2, 5.8, 'Origin responds'),
    (5.8, 6.3, 'Varnish3 caches the object'),
    (6.3, 7.9, 'Answers client, notifies peers'),
    (7.9, 8.8, 'Peers pull it from Varnish3'),
    (8.8, 10.1, 'Copying to Varnish1 & Varnish2'),
)


def vha_style():
    L = VHA_LOOP
    css = ['<style class="vclski-animation">\n', preamble(L)]
    css.append('''  .vk-wave, .vk-glow { animation-timing-function: ease-out; }
  .vk-wave { transform-origin: %spx %spx; }
  .vk-curve { offset-path: path("%s"); }
  .vk-flight-v2 { offset-path: path("%s"); }
  .vk-flight-v1 { offset-path: path("%s"); }
  .vk-curve, .vk-flight-v2, .vk-flight-v1 { offset-rotate: 0deg; }
  .vk-obj { animation: vk-store-v3 %ss infinite linear; }
  .vk-store-v2 { animation-name: vk-store-v2; }
  .vk-store-v1 { animation-name: vk-store-v1; }
''' % (VHA_V3_CENTRE[0], VHA_V3_CENTRE[1], VHA_CURVE, VHA_FLIGHT_V2,
       VHA_FLIGHT_V1, L))
    css.append(names_css(
        ['vk-get', 'vk-miss', 'vk-fill', 'vk-deliver', 'vk-pull-v2',
         'vk-pull-v1', 'vk-give-v2', 'vk-give-v1', 'vk-glow-v2', 'vk-glow-v1']
        + ['vk-wave-%d' % i for i in range(len(VHA_WAVES))]))
    css.append(easing_css([
        ('vk-miss', EASE_HAUL), ('vk-fill', EASE_HAUL),
        ('vk-pull-v2', EASE_LOCAL), ('vk-pull-v1', EASE_LOCAL),
        ('vk-give-v2', EASE_LOCAL), ('vk-give-v1', EASE_LOCAL),
    ]))
    css.append(progress_css(L, VHA_PROGRESS_Y))
    css.append(legend_css(L, VHA_LEGEND_SWIPE, VHA_HOLD, VHA_LEGEND))
    css.append(captions_css(L, VHA_CAPTIONS))
    css.append('\n  /* Client and origin traffic, riding the drawn curve */\n')
    css.append(leg(L, 'vk-get', VHA_GET, VHA_START, VHA_V3))
    css.append(leg(L, 'vk-miss', VHA_MISS, VHA_V3, VHA_ORIGIN))
    css.append(leg(L, 'vk-fill', VHA_FILL, VHA_ORIGIN, VHA_V3))
    css.append(leg(L, 'vk-deliver', VHA_DELIVER, VHA_V3, VHA_CLIENT))
    css.append('  /* "Object available" broadcast, radiating from Varnish3 */\n')
    for i, span in enumerate(VHA_WAVES):
        css.append(kf(L, 'vk-wave-%d' % i, span, 'transform', 'scale(0.15)',
                      'scale(%s)' % VHA_WAVE_SCALE, opacity=0.45))
    css.append('  /* ...lighting up each peer as it arrives */\n')
    css.append(kf_hold(L, 'vk-glow-v2', VHA_GLOW_V2, opacity=0.9))
    css.append(kf_hold(L, 'vk-glow-v1', VHA_GLOW_V1, opacity=0.9))
    css.append('  /* Notified peers request the object straight from Varnish3 */\n')
    css.append(leg(L, 'vk-pull-v2', VHA_PULL_V2, 0, 100))
    css.append(leg(L, 'vk-pull-v1', VHA_PULL_V1, 0, 100))
    css.append('  /* ...and it flies back to each of them */\n')
    css.append(leg(L, 'vk-give-v2', VHA_GIVE_V2, 100, 0))
    css.append(leg(L, 'vk-give-v1', VHA_GIVE_V1, 100, 0))
    css.append('  /* Cached copies of the orange object, landing with a spring */\n')
    at_by_class = {'vk-store-v3': VHA_STORE_V3, 'vk-store-v2': VHA_STORE_V2,
                   'vk-store-v1': VHA_STORE_V1}
    for translate, cls in VHA_OBJECTS.items():
        css.append(kf_stored(L, cls, at_by_class[cls], VHA_HOLD, translate))
    css.append(REDUCED_MOTION)
    return ''.join(css)


def vha_defs():
    x, y, w, h = VHA_CLUSTER_BOX
    return ('<clipPath id="vk-cluster-clip"><rect x="%s" y="%s" width="%s" '
            'height="%s" rx="8"/></clipPath>\n' % (x, y, w, h))


def vha_packets():
    out = ['<g class="vclski-packets">\n', '  <g clip-path="url(#vk-cluster-clip)">\n']
    for i in range(len(VHA_WAVES)):
        out.append('    <circle class="vk-wave vk-wave-%d" cx="%s" cy="%s" r="%s" '
                   'fill="none" stroke="%s" stroke-width="2.5" '
                   'vector-effect="non-scaling-stroke"/>\n'
                   % (i, VHA_V3_CENTRE[0], VHA_V3_CENTRE[1], VHA_WAVE_R, SIGNAL))
    out.append('  </g>\n')
    for node, (x, y, w, h) in VHA_PEER_BOXES.items():
        out.append('  <rect class="vk-glow vk-glow-%s" x="%s" y="%s" width="%s" '
                   'height="%s" rx="10" fill="none" stroke="%s" '
                   'stroke-width="3"/>\n'
                   % (node, x + VHA_GLOW_INSET, y + VHA_GLOW_INSET,
                      w - 2 * VHA_GLOW_INSET, h - 2 * VHA_GLOW_INSET, SIGNAL))
    out.append('  <g transform="%s">\n' % VHA_CURVE_GROUP)
    for frag in (ring('vk-curve vk-get', OBJECT_FILL),
                 ring('vk-curve vk-miss', OBJECT_FILL),
                 disc('vk-curve vk-fill'), disc('vk-curve vk-deliver')):
        out.append('  ' + frag)
    out.append('  </g>\n')
    out.append(ring('vk-flight-v2 vk-pull-v2', OBJECT_FILL))
    out.append(ring('vk-flight-v1 vk-pull-v1', OBJECT_FILL))
    out.append(disc('vk-flight-v2 vk-give-v2', r=6.0))
    out.append(disc('vk-flight-v1 vk-give-v1', r=6.0))
    out.append(legend_svg(VHA_LEGEND))
    out.append(progress_svg(VHA_PROGRESS_Y, VHA_WIDTH))
    out.append(captions_svg(VHA_CAPTIONS))
    out.append('</g>\n')
    return ''.join(out)


# ===========================================================================
# Varnish Cluster
# ===========================================================================

CL_CURVE = ('M0.68 -0.02 C7.53 8.26, 35.12 28.34, 40.01 50.71 C44.89 73.07, '
            '5.75 114.06, 30 134.17 C54.25 154.28, 143.47 158.86, 185.51 '
            '171.37 C227.54 183.88, 267.26 195.19, 282.22 209.23 C297.18 '
            '223.27, 300.88 254.68, 275.27 255.59 C249.66 256.5, 169.28 '
            '223.46, 128.57 214.69 C87.85 205.92, 45.19 197.99, 30.97 202.97 '
            'C16.76 207.94, 46.98 232.53, 43.27 244.53 C39.56 256.54, 12.92 '
            '258.27, 8.71 274.98 C4.49 291.7, 16.65 323.83, 17.98 344.85 '
            'C19.31 365.87, 16.89 391.67, 16.67 401.11')
CL_CURVE_GROUP = 'translate(349.5993041992185 38.50000762939408)'

# Waypoints along that curve, as a percentage of its arc length. The drawn
# curve already traces the whole self-routing round trip: out past the client,
# into Varnish3, back left to Varnish2, then down to the origin.
CL_START, CL_CLIENT, CL_V3, CL_V2, CL_ORIGIN = 0.0, 12.0, 50.0, 85.0, 100.0

# Only the orange object is animated; the green ones are already cached.
CL_OBJECTS = {
    '315.79986572265625 309.7048001243729': 'vk-store-v2',  # owner caches it
    '552.2000122070312 308.5046963646073': 'vk-store-v3',   # then the edge does
}

CL_LOOP = 12.0
CL_GET = (0.4, 2.0)       # Client -> Varnish3
CL_ROUTE = (2.4, 3.8)     # Varnish3 self-routes to the owning node, Varnish2
CL_MISS = (4.2, 5.4)      # Varnish2 -> Origin
CL_FILL = (5.8, 7.0)      # Origin -> Varnish2 (carrying the object)
CL_STORE_V2 = 7.0         # Varnish2 caches it
CL_HAND = (7.4, 8.8)      # Varnish2 -> Varnish3
CL_STORE_V3 = 8.8         # Varnish3 caches it too
CL_DELIVER = (9.2, 10.6)  # Varnish3 -> Client
CL_HOLD = 11.4
CL_CANVAS_H = 550.8861336844984  # height of the Excalidraw export
CL_CANVAS_PAD = 16               # empty strip added below it
CL_PROGRESS_Y = CL_CANVAS_H + CL_CANVAS_PAD / 2
CL_WIDTH = 686.8

# This setup is full replication, the first of the three legend lines.
CL_LEGEND = (466.04, 375.04, 174.58, 19.5)    # "Full replication"
CL_LEGEND_SWIPE = (9.0, 9.35)

CL_CAPTIONS = (
    (0.4, 2.2, 'GET: client asks Varnish3'),
    (2.2, 3.9, 'Self-routing to Varnish2'),
    (3.9, 5.6, 'MISS: fetching from the origin'),
    (5.6, 7.2, 'Origin responds to Varnish2'),
    (7.2, 8.9, 'Varnish2 caches it, hands it on'),
    (8.9, 10.7, 'Varnish3 caches it, answers client'),
)


def cluster_style():
    L = CL_LOOP
    css = ['<style class="vclski-animation">\n', preamble(L)]
    css.append('''  .vk-curve { offset-path: path("%s"); offset-rotate: 0deg; }
  .vk-obj { animation: vk-store-v2 %ss infinite linear; }
  .vk-store-v3 { animation-name: vk-store-v3; }
''' % (CL_CURVE, L))
    css.append(names_css(['vk-get', 'vk-route', 'vk-miss', 'vk-fill',
                          'vk-hand', 'vk-deliver']))
    css.append(easing_css([
        ('vk-miss', EASE_HAUL), ('vk-fill', EASE_HAUL),
        ('vk-route', EASE_LOCAL), ('vk-hand', EASE_LOCAL),
    ]))
    css.append(progress_css(L, CL_PROGRESS_Y))
    css.append(legend_css(L, CL_LEGEND_SWIPE, CL_HOLD, CL_LEGEND))
    css.append(captions_css(L, CL_CAPTIONS))
    css.append('\n  /* The client asks Varnish3, which does not own the object */\n')
    css.append(leg(L, 'vk-get', CL_GET, CL_START, CL_V3))
    css.append('  /* ...so it self-routes the request to Varnish2, which owns it */\n')
    css.append(leg(L, 'vk-route', CL_ROUTE, CL_V3, CL_V2))
    css.append('  /* MISS on Varnish2: fetch from the origin */\n')
    css.append(leg(L, 'vk-miss', CL_MISS, CL_V2, CL_ORIGIN))
    css.append('  /* The object comes back to Varnish2, which caches it */\n')
    css.append(leg(L, 'vk-fill', CL_FILL, CL_ORIGIN, CL_V2))
    css.append('  /* ...hands it back to Varnish3, which caches it too */\n')
    css.append(leg(L, 'vk-hand', CL_HAND, CL_V2, CL_V3))
    css.append('  /* ...and Varnish3 answers the client */\n')
    css.append(leg(L, 'vk-deliver', CL_DELIVER, CL_V3, CL_CLIENT))
    css.append('  /* Cached copies of the orange object, landing with a spring */\n')
    at_by_class = {'vk-store-v2': CL_STORE_V2, 'vk-store-v3': CL_STORE_V3}
    for translate, cls in CL_OBJECTS.items():
        css.append(kf_stored(L, cls, at_by_class[cls], CL_HOLD, translate))
    css.append(REDUCED_MOTION)
    return ''.join(css)


def cluster_packets():
    out = ['<g class="vclski-packets">\n', '  <g transform="%s">\n' % CL_CURVE_GROUP]
    for frag in (ring('vk-curve vk-get', OBJECT_FILL),
                 ring('vk-curve vk-route', OBJECT_FILL),
                 ring('vk-curve vk-miss', OBJECT_FILL),
                 disc('vk-curve vk-fill'),
                 disc('vk-curve vk-hand'),
                 disc('vk-curve vk-deliver')):
        out.append('  ' + frag)
    out.append('  </g>\n')
    out.append(legend_svg(CL_LEGEND))
    out.append(progress_svg(CL_PROGRESS_Y, CL_WIDTH))
    out.append(captions_svg(CL_CAPTIONS))
    out.append('</g>\n')
    return ''.join(out)


# ===========================================================================
# Patching
# ===========================================================================

def accessible_names(title, desc):
    """An accessible name and description for the diagram."""
    return ('<title>%s</title><desc>%s</desc>'
            % (title, desc.replace('&', '&amp;')))


def patch(name, style, packets, objects, checks, extra_defs='', a11y=None,
          canvas=None):
    source = os.path.join(HERE, '%s-static.svg' % name)
    target = os.path.join(HERE, '%s.svg' % name)
    with open(source, encoding='utf-8') as f:
        svg = f.read()

    def expect(needle, what, count=1):
        if svg.count(needle) != count:
            sys.exit('%s-static.svg: expected %d x %s (%r), found %d. The export '
                     'geometry changed; update animate-diagrams.py.'
                     % (name, count, what, needle[:50], svg.count(needle)))

    for needle, what, count in checks:
        expect(needle, what, count)

    expect('</defs>', 'defs block')
    svg = svg.replace('</defs>', style() + extra_defs + '</defs>')

    if canvas:
        svg = extend_canvas(svg, *canvas)

    if a11y:
        # Give the diagram an accessible name. Neither element renders, so the
        # animation-off fallback stays pixel-identical to the static export.
        head = svg.index('>', svg.index('<svg '))
        svg = svg[:head] + ' role="img"' + svg[head:]
        head = svg.index('>', svg.index('<svg ')) + 1
        svg = svg[:head] + accessible_names(*a11y) + svg[head:]

    for translate, cls in objects.items():
        needle = '<g stroke-linecap="round" transform="translate(%s)' % translate
        expect(needle, 'cached object group')
        svg = svg.replace(needle, '<g class="vk-obj %s" stroke-linecap="round" '
                                  'transform="translate(%s)' % (cls, translate))

    svg = svg.rstrip()
    if not svg.endswith('</svg>'):
        sys.exit('%s-static.svg: unexpected trailing content.' % name)
    svg = svg[:-len('</svg>')] + packets() + '</svg>'

    with open(target, 'w', encoding='utf-8') as f:
        f.write(svg)
    print('%s-static.svg -> %s' % (name, os.path.basename(target)))


if __name__ == '__main__':
    # The curve each set of packets rides must be the one actually drawn, in
    # the coordinate space we assume. A curve's transform is shared with its
    # two arrowhead groups, hence three occurrences.
    patch('replication-vha', vha_style, vha_packets, VHA_OBJECTS, checks=[
        ('d="%s"' % VHA_CURVE, 'GET annotation curve', 1),
        ('transform="%s rotate' % VHA_CURVE_GROUP, 'GET annotation group', 3),
        ('transform="translate(%s %s)' % (VHA_CLUSTER_BOX[0], VHA_CLUSTER_BOX[1]),
         'VHA cluster box', 1),
    ], extra_defs=vha_defs(), canvas=(VHA_CANVAS_H, VHA_CANVAS_PAD), a11y=(
        'VHA replication',
        'A client GET misses on Varnish3, which fetches the object from the '
        'origin, caches it and answers the client, then broadcasts a '
        'notification to its peers. Varnish1 and Varnish2 pull the object '
        'straight from Varnish3 and cache it, reaching full replication.'))

    patch('replication-cluster', cluster_style, cluster_packets, CL_OBJECTS, checks=[
        ('d="%s"' % CL_CURVE, 'GET annotation curve', 1),
        ('transform="%s rotate' % CL_CURVE_GROUP, 'GET annotation group', 3),
    ], canvas=(CL_CANVAS_H, CL_CANVAS_PAD), a11y=(
        'Varnish Cluster replication',
        'Nothing is cached yet. A client GET reaches Varnish3, which does not '
        'own the object, so it self-routes the request to Varnish2. Varnish2 '
        'misses, fetches from the origin and caches the object, then hands it '
        'to Varnish3, which caches it too and answers the client.'))
