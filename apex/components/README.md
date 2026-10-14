# HarvestLink Template Components

APEX Template Components (plug-ins) that output the HarvestLink design system's own markup, so APEX pages look like
the design canvas. `scripts/install_app.py` adds every folder here to the app on each build; pages use them as
regions of type `appTemplateComponent/<name>` with a SQL query and `settings { attribute: &COLUMN. }`.

| Component | Design system component | Use as |
|---|---|---|
| `hlStatCard` | StatCard | single or report (grid of cards) |
| `hlFulfilmentBar` | FulfilmentBar | single |
| `hlMatchCard` | MatchCard (four reasons, optional confirm link) | report |
| `hlDemandCard` | Canvas landing "open demand" card | report |
| `hlPageHeader` | PageHeader | single |
| `hlAlert` | Alert | single |
| `hlGradeTag`, `hlStatusBadge`, `hlProvenanceTag` | GradeTag, StatusBadge, ProvenanceTag | single |

The files are generated: edit `scripts/gen_template_components.py` and run it, rather than editing the `.apx`
files. The markup was taken from the design system's React components rendered to HTML, and the styles come from
`apex/theme/design-system/` (copied from the canvas).
