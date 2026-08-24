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
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

FADE = 0.15               # opacity ramp in/out for every packet
OBJECT_FILL = '#fab005'   # matches the drawn orange object
SIGNAL = '#1971c2'        # matches the drawn cluster boundary
INK = '#1e1e1e'


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


def kf_stored(loop, name, at, hold):
    """Fade a cached object in, then out again as the loop resets."""
    return '''  @keyframes %s {
    0%%, %s   { opacity: 0; }
    %s, %s    { opacity: 1; }
    %s, 100%% { opacity: 0; }
  }
''' % (name, pct(loop, at), pct(loop, at + 0.3), pct(loop, hold),
       pct(loop, loop - 0.2))


def leg(loop, name, span, frm, to):
    """A packet travelling between two waypoints on a curve."""
    return kf(loop, name, span, 'offset-distance', '%s%%' % frm, '%s%%' % to)


def ring(cls, stroke, r=5.5):
    """A request or a notification: hollow, because it carries no payload."""
    return ('  <circle class="vk-pkt %s" r="%s" fill="#ffffff" stroke="%s" '
            'stroke-width="2.5"/>\n' % (cls, r, stroke))


def disc(cls, r=6.5):
    """The object itself, in flight."""
    return ('  <circle class="vk-pkt %s" r="%s" fill="%s" stroke="%s" '
            'stroke-width="1.5"/>\n' % (cls, r, OBJECT_FILL, INK))


def preamble(loop, extra=''):
    return '''  /* VCLSKi: animation overlay generated by animate-diagrams.py.
     Do not hand-edit; regenerate instead. Every animated element is
     hidden by default and only revealed inside a keyframe, so renderers
     without CSS animation support fall back to the static diagram. */
  .vk-pkt%s {
    opacity: 0;
    animation-duration: %ss;
    animation-iteration-count: infinite;
  }
  .vk-pkt { animation-timing-function: ease-in-out; }
%s''' % (extra, loop, '')


def names_css(names):
    return ''.join('  .%s { animation-name: %s; }\n' % (n, n) for n in names)


REDUCED_MOTION = '''
  @media (prefers-reduced-motion: reduce) {
    %s { display: none; }
    .vk-obj { animation: none; opacity: 1; }
  }
</style>
'''


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


def vha_style():
    L = VHA_LOOP
    css = ['<style class="vclski-animation">\n', preamble(L, ', .vk-wave, .vk-glow')]
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
    css.append('  /* Cached copies of the orange object */\n')
    for name, at in (('vk-store-v3', VHA_STORE_V3), ('vk-store-v2', VHA_STORE_V2),
                     ('vk-store-v1', VHA_STORE_V1)):
        css.append(kf_stored(L, name, at, VHA_HOLD))
    css.append(REDUCED_MOTION % '.vk-pkt, .vk-wave, .vk-glow')
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


def cluster_style():
    L = CL_LOOP
    css = ['<style class="vclski-animation">\n', preamble(L)]
    css.append('''  .vk-curve { offset-path: path("%s"); offset-rotate: 0deg; }
  .vk-obj { animation: vk-store-v2 %ss infinite linear; }
  .vk-store-v3 { animation-name: vk-store-v3; }
''' % (CL_CURVE, L))
    css.append(names_css(['vk-get', 'vk-route', 'vk-miss', 'vk-fill',
                          'vk-hand', 'vk-deliver']))
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
    css.append('  /* Cached copies of the orange object */\n')
    css.append(kf_stored(L, 'vk-store-v2', CL_STORE_V2, CL_HOLD))
    css.append(kf_stored(L, 'vk-store-v3', CL_STORE_V3, CL_HOLD))
    css.append(REDUCED_MOTION % '.vk-pkt')
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
    out.append('  </g>\n</g>\n')
    return ''.join(out)


# ===========================================================================
# Patching
# ===========================================================================

def patch(name, style, packets, objects, checks, extra_defs=''):
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
    ], extra_defs=vha_defs())

    patch('replication-cluster', cluster_style, cluster_packets, CL_OBJECTS, checks=[
        ('d="%s"' % CL_CURVE, 'GET annotation curve', 1),
        ('transform="%s rotate' % CL_CURVE_GROUP, 'GET annotation group', 3),
    ])
