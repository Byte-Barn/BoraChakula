"""Usage: python scripts/gen_template_components.py [out_dir]  (default apex/components)

Generate HarvestLink APEX Template Components (APEXlang) from compact specs.
Markup copies the design system's React components (rendered with react-dom/server)."""
import os, sys, textwrap
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apex", "components")
BT = "```"
SVG = '<svg width="{s}" height="{s}" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><path d="{d}"></path></svg>'
ICON = {
 "circleCheck": "M8 1.75a6.25 6.25 0 1 0 0 12.5A6.25 6.25 0 0 0 8 1.75zM5.25 8.25l2 2 3.5-4",
 "clock": "M8 1.75a6.25 6.25 0 1 0 0 12.5A6.25 6.25 0 0 0 8 1.75zM8 4.5V8l2.5 1.5",
 "circleDash": "M8 1.75a6.25 6.25 0 1 0 0 12.5A6.25 6.25 0 0 0 8 1.75zM5.25 8h5.5",
 "check": "M3.5 8.5l3 3 6-7", "truck": "M1.75 4h7.5v6.5h-7.5zM9.25 6.5h3l2 2.25v1.75h-5M4.5 12.5a1.25 1.25 0 1 0 0-.01M11.5 12.5a1.25 1.25 0 1 0 0-.01",
 "calendar": "M2.25 3.5h11.5v10.25H2.25zM2.25 6.5h11.5M5 2v3M11 2v3", "arrowLeft": "M13 8H3M7 4L3 8l4 4", "arrowRight": "M3 8h10M9 4l4 4-4 4",
 "alert": "M8 2L1.75 13.25h12.5zM8 6.5v3M8 11.25v.25", "info": "M8 1.75a6.25 6.25 0 1 0 0 12.5A6.25 6.25 0 0 0 8 1.75zM8 7.25v4M8 4.75v.25",
}
def icon(n, s=16): return SVG.format(s=s, d=ICON[n])

def status_badge(st, txt):
    return ("{case %s/}{when matched/}%s{when confirmed/}%s{when delivered/}%s{when transit/}%s{when scheduled/}%s"
            "{when pending/}%s{when awaiting/}%s{otherwise/}%s{endcase/}") % (st,
        icon("circleCheck",14), icon("circleCheck",14), icon("check",14), icon("truck",14), icon("calendar",14),
        icon("clock",14), icon("clock",14), icon("circleDash",14)) + txt

STATUS_TEXT = ("{case %s/}{when matched/}Matched{when confirmed/}Confirmed{when delivered/}Delivered{when transit/}In transit"
               "{when scheduled/}Pickup scheduled{when pending/}Pending{when awaiting/}Awaiting farmer{when unmatched/}Unmatched"
               "{when cancelled/}Cancelled{when draft/}Draft{otherwise/}#%s#{endcase/}")
PROV_TEXT = ("{case %s/}{when live/}Live data{when sourced/}Sourced{when simulated/}Simulated{when demo/}Demo data"
             "{when roadmap/}Roadmap{otherwise/}#%s#{endcase/}")
GRADE_TEXT = "{case %s/}{when A/}Grade A · Premium{when B/}Grade B · Market{when C/}Grade C · Processing{otherwise/}Grade #%s#{endcase/}"

def grade_tag(attr, compact_attr=None):
    inner = "<span>" + GRADE_TEXT % (attr, attr) + "</span>"
    if compact_attr:
        inner = "{if %s/}<span class=\"hl-sr\">Grade #%s#</span>{else/}%s{endif/}" % (compact_attr, attr, inner)
    return ('<span class="hl-grade hl-grade-{case %s/}{when A/}a{when B/}b{otherwise/}c{endcase/}" title="Grade #%s!ATTR#">'
            '<b aria-hidden="true">#%s#</b>%s</span>') % (attr, attr, attr, inner)

def reason(n):
    st = f"REASON{n}_STATE"
    return ("{if ?REASON%d_LABEL/}<li class=\"hl-{case %s/}{when warn/}warn{when no/}no{otherwise/}ok{endcase/}\">"
            "{case %s/}{when warn/}%s{when no/}%s{otherwise/}%s{endcase/}<div><b>#REASON%d_LABEL#</b><span>#REASON%d_DETAIL#</span></div></li>{endif/}") % (
            n, st, st, icon("clock"), icon("circleDash"), icon("circleCheck"), n, n)

C = {}
C["hlProvenanceTag"] = dict(name="HL Provenance Tag", help="Where a number comes from: live, sourced, simulated, demo or roadmap (HarvestLink design system ProvenanceTag).",
  partial='<span class="hl-prov hl-prov-#KIND!ATTR#" title="#TITLE!ATTR#">{if ?TEXT/}#TEXT#{else/}' + PROV_TEXT % ("KIND","KIND") + '{endif/}</span>',
  attrs=[("KIND","kind","Kind"),("TEXT","text","Text"),("TITLE","title","Title")])
C["hlStatusBadge"] = dict(name="HL Status Badge", help="A status word with its glyph, never colour alone (HarvestLink design system StatusBadge).",
  partial='<span class="hl-badge hl-badge-#STATUS!ATTR#">' + status_badge("STATUS", "{if ?TEXT/}#TEXT#{else/}" + STATUS_TEXT % ("STATUS","STATUS") + "{endif/}") + '</span>',
  attrs=[("STATUS","status","Status"),("TEXT","text","Text")])
C["hlGradeTag"] = dict(name="HL Grade Tag", help="Produce grade letter with its outlet class (HarvestLink design system GradeTag).",
  partial=grade_tag("GRADE","COMPACT"), attrs=[("GRADE","grade","Grade"),("COMPACT","compact","Compact (Y/N)")])
C["hlStatCard"] = dict(name="HL Stat Card", help="One metric with unit, provenance and a How this is calculated note (HarvestLink design system StatCard).",
  partial=('<section class="hl-stat" aria-label="#LABEL!ATTR#"><div class="hl-stat-top"><p class="hl-stat-label">#LABEL#</p>'
           '{if ?PROVENANCE/}<span class="hl-prov hl-prov-#PROVENANCE!ATTR#">' + PROV_TEXT % ("PROVENANCE","PROVENANCE") + '</span>{endif/}</div>'
           '<p class="hl-stat-value hl-num">#VALUE#{if ?UNIT/}<small>#UNIT#</small>{endif/}</p>'
           '{if ?DELTA/}<p class="hl-stat-delta">#DELTA#</p>{endif/}'
           '{if ?METHOD/}<details><summary>How this is calculated</summary><p class="hl-stat-method">#METHOD#</p></details>{endif/}</section>'),
  report_body='<div class="hl-stat-grid #APEX$COMPONENT_CSS_CLASSES#">#APEX$ROWS#</div>', report_row='<div #APEX$ROW_IDENTIFICATION#>#APEX$PARTIAL#</div>',
  attrs=[("LABEL","label","Label"),("VALUE","value","Value"),("UNIT","unit","Unit"),("PROVENANCE","provenance","Provenance"),("DELTA","delta","Delta"),("METHOD","method","Method")])
C["hlFulfilmentBar"] = dict(name="HL Fulfilment Bar", help="Progress of a demand: matched, pending and unmatched kg (HarvestLink design system FulfilmentBar). Pass widths as numbers 0-100.",
  partial=('<div class="hl-fill"><div class="hl-fill-head"><span class="hl-fill-total hl-num">#SOURCED#<small> of #TARGET# kg sourced</small></span>'
           '<span class="hl-help">#CONFIRMED_PCT#% confirmed</span></div>'
           '<div class="hl-fill-track" role="img" aria-label="#MATCHED# kg matched, #PENDING# pending, #UNMATCHED# unmatched of #TARGET#">'
           '<span class="hl-fill-seg hl-fill-matched" style="width:#MATCHED_WIDTH#%"></span><span class="hl-fill-seg hl-fill-pending" style="width:#PENDING_WIDTH#%"></span></div>'
           '{if LEGEND/}<ul class="hl-fill-legend"><li><span class="hl-key hl-key-matched"></span>#MATCHED_LABEL# <b class="hl-num">#MATCHED# kg</b></li>'
           '<li><span class="hl-key hl-key-pending"></span>#PENDING_LABEL# <b class="hl-num">#PENDING# kg</b></li>'
           '<li><span class="hl-key hl-key-unmatched"></span>#UNMATCHED_LABEL# <b class="hl-num">#UNMATCHED# kg</b></li></ul>{endif/}</div>'),
  attrs=[("SOURCED","sourced","Sourced kg (formatted)"),("TARGET","target","Target kg (formatted)"),("CONFIRMED_PCT","confirmedPct","Confirmed %"),
         ("MATCHED","matched","Matched kg (formatted)"),("PENDING","pending","Pending kg (formatted)"),("UNMATCHED","unmatched","Unmatched kg (formatted)"),
         ("MATCHED_WIDTH","matchedWidth","Matched width %"),("PENDING_WIDTH","pendingWidth","Pending width %"),("LEGEND","legend","Show legend (Y/N)"),
         ("MATCHED_LABEL","matchedLabel","Matched label"),("PENDING_LABEL","pendingLabel","Pending label"),("UNMATCHED_LABEL","unmatchedLabel","Unmatched label")])
C["hlMatchCard"] = dict(name="HL Match Card", help="One farmer's supply against a demand with rank, grade, status and the four reasons (HarvestLink design system MatchCard).",
  partial=('<article class="hl-match{if ?STATUS/} hl-match-#STATUS!ATTR#{endif/}">{if ?RANK/}<span class="hl-match-rank" aria-label="Rank #RANK!ATTR#">#RANK#</span>{endif/}'
           '<div><h3 class="hl-match-name">#FARMER#</h3><p class="hl-match-meta"><span>#LOCATION#</span>{if ?DISTANCE/}<span class="hl-num">#DISTANCE#</span>{endif/}{if ?HARVEST/}<span>Harvest #HARVEST#</span>{endif/}</p></div>'
           '<div class="hl-match-qty"><strong>#QTY#</strong><span>#QTY_LABEL#</span></div>'
           '<div class="hl-match-tags">' + grade_tag("GRADE") + '{if ?STATUS/}<span class="hl-badge hl-badge-#STATUS!ATTR#">' + status_badge("STATUS", "{if ?STATUS_TEXT/}#STATUS_TEXT#{else/}" + STATUS_TEXT % ("STATUS","STATUS") + "{endif/}") + '</span>{endif/}</div>'
           '<details{if OPEN/} open{endif/}><summary>#REASONS_TITLE#</summary><ul class="hl-reasons">' + "".join(reason(i) for i in range(1,5)) + '</ul></details>'
           '{if ?ACTION_URL/}<div class="hlc-match-action"><a class="hl-btn hl-btn-secondary hl-btn-sm" href="#ACTION_URL!ATTR#">' + icon("check") + '#ACTION_LABEL#</a>{if ?ACTION_NOTE/}<span>#ACTION_NOTE#</span>{endif/}</div>{endif/}'
           '</article>'),
  report_body='<div class="hlc-match-list #APEX$COMPONENT_CSS_CLASSES#">#APEX$ROWS#</div>', report_row='<div #APEX$ROW_IDENTIFICATION#>#APEX$PARTIAL#</div>',
  attrs=[("RANK","rank","Rank"),("STATUS","status","Status"),("STATUS_TEXT","statusText","Status text"),("FARMER","farmer","Farmer"),("LOCATION","location","Location"),
         ("DISTANCE","distance","Distance text"),("HARVEST","harvest","Harvest window"),("QTY","qty","Quantity"),("QTY_LABEL","qtyLabel","Quantity label"),("GRADE","grade","Grade"),
         ("OPEN","open","Reasons open (Y/N)"),("REASONS_TITLE","reasonsTitle","Reasons title")] +
        [(f"REASON{i}_{p}", f"reason{i}{p.title()}", f"Reason {i} {p.lower()}") for i in range(1,5) for p in ("LABEL","DETAIL","STATE")] +
        [("ACTION_URL","actionUrl","Action URL"),("ACTION_LABEL","actionLabel","Action label"),("ACTION_NOTE","actionNote","Action note")])
C["hlPageHeader"] = dict(name="HL Page Header", help="Top of an app page: back link, eyebrow, the page's h1 and a description (HarvestLink design system PageHeader).",
  partial=('<header class="hl-ph">{if ?BACK_URL/}<a class="hl-ph-back hl-link" href="#BACK_URL!ATTR#" style="text-decoration:none">' + icon("arrowLeft",14) + '#BACK_LABEL#</a>{endif/}'
           '{if ?EYEBROW/}<span class="hl-overline">#EYEBROW#</span>{endif/}<div class="hl-ph-row"><div class="hl-stack" style="gap:4px"><h1>#TITLE#</h1>{if ?DESCRIPTION/}<p>#DESCRIPTION#</p>{endif/}</div></div></header>'),
  attrs=[("TITLE","title","Title"),("EYEBROW","eyebrow","Eyebrow"),("DESCRIPTION","description","Description"),("BACK_LABEL","backLabel","Back label"),("BACK_URL","backUrl","Back URL")])
C["hlAlert"] = dict(name="HL Alert", help="Page or form message for info, success, warning and error (HarvestLink design system Alert).",
  partial=('<div class="hl-alert hl-alert-#TONE!ATTR#" role="status">{case TONE/}{when success/}' + icon("circleCheck",18) + '{when warning/}' + icon("alert",18) +
           '{when error/}' + icon("alert",18) + '{otherwise/}' + icon("info",18) + '{endcase/}<div>{if ?TITLE/}<b>#TITLE#</b>{endif/}#BODY#{if ?LINK_URL/} <a class="hl-link" href="#LINK_URL!ATTR#">#LINK_LABEL#</a>{endif/}</div></div>'),
  attrs=[("TONE","tone","Tone"),("TITLE","title","Title"),("BODY","body","Body"),("LINK_URL","linkUrl","Link URL"),("LINK_LABEL","linkLabel","Link label")])
C["hlDemandCard"] = dict(name="HL Demand Card", help="Open demand card with crop photo, grade, quantity and fill bar (canvas landing page).",
  partial=('<article class="hlc-card hlc-demand"><div class="hlc-demand-img"><img src="#IMAGE_URL!ATTR#" alt="#CROP!ATTR#"><span class="hlc-demand-grade">' + grade_tag("GRADE","COMPACT") + '</span></div>'
           '<div class="hlc-demand-body"><div><h3>#CROP#</h3><p class="hlc-muted">#BUYER#</p></div><div class="hlc-demand-row"><span class="hlc-demand-qty">#QTY#</span><span class="hlc-muted">#DATE#</span></div>'
           '<div class="hlc-demand-track"><div style="width:#FILL_PCT#%"></div></div><p class="hlc-muted">#FILLED#</p></div></article>'),
  report_body='<div class="hlc-demand-grid #APEX$COMPONENT_CSS_CLASSES#">#APEX$ROWS#</div>', report_row='<div #APEX$ROW_IDENTIFICATION#>#APEX$PARTIAL#</div>',
  attrs=[("IMAGE_URL","imageUrl","Image URL"),("CROP","crop","Crop"),("BUYER","buyer","Buyer"),("GRADE","grade","Grade"),("COMPACT","compact","Compact grade (Y/N)"),
         ("QTY","qty","Quantity"),("DATE","date","Date"),("FILL_PCT","fillPct","Fill %"),("FILLED","filled","Fill text")])

def write(name, spec):
    d = os.path.join(OUT, name); os.makedirs(d, exist_ok=True)
    avail = ["partial"] + (["report"] if "report_body" in spec else [])
    ind = lambda t: textwrap.indent(t, " " * 12)
    out = [f"plugin {name} (", f"    name: {spec['name']}", f"    staticId: HL_{name[2:].upper()}" if False else f"    staticId: COM.HARVESTLINK.{name[2:].upper()}",
           "    templateComponent {", "        availableAs: [" ] + [f"            {a}" for a in avail] + ["        ]",
           "        partial:", f"            {BT}html", ind(spec["partial"]), f"            {BT}"]
    if "report_body" in spec:
        out += ["        reportBody:", f"            {BT}html", ind(spec["report_body"]), f"            {BT}",
                "        reportRow:", f"            {BT}html", ind(spec["report_row"]), f"            {BT}"]
    out += ["        translateTemplates: false", "    }", "    component {", "        standardAttributes: regionTemplateAttr", "    }",
            "    information {", f"        helpText: {spec['help']}", "    }", ")", ""]
    open(os.path.join(d, "plugin.apx"), "w").write("\n".join(out))
    ca = []
    for i, (static, apexname, label) in enumerate(spec["attrs"], 1):
        ca += [f"customAttribute {static} (", f"    apexlangName: {apexname}", f"    attribute: {i}", f"    name: {label}",
               "    appearance {", f"        sequence: {i * 10}", "    }", ")", ""]
    open(os.path.join(d, "custom-attributes.apx"), "w").write("\n".join(ca))
for n, s in C.items(): write(n, s)
print("wrote", len(C), "components:", ", ".join(C))
