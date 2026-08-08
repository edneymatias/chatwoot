# Phase 35: Search (and Sort/Filter) for Opportunities

**Status**: placeholder — pending brainstorm session

**Depends on**: Phase 8 (List View), which is the primary surface this will operate on, though
search may also apply to the Kanban board.

## Quick Preview

A way to find opportunities beyond scrolling stage columns or paging through the list view —
likely a search input (by title/contact) plus filter and sort controls, grouped together as one
feature since they all answer "which opportunities am I looking at right now." Needs design for:
what fields are searchable/filterable (title, contact, assignee, stage, value range, status),
whether search/filter applies to both the Kanban and list views or just the list, what sort
options are offered (e.g. by value, by last activity, by stage), whether results update the
existing views in place or open a separate results view, and whether filter state is persisted
(URL params, localStorage) or resets on navigation.
