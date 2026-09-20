# The wiki, as files

These are the pages of [the GitHub wiki](https://github.com/victormlourenco/ROSilicon/wiki),
kept here so they are reviewed and versioned with the code rather than edited
into a box in a browser. `tools/publish-wiki.sh` copies them over; it mirrors
this folder, so a page deleted here is deleted there.

```
Home.md               the landing page, and the choice of language
Getting-Started.md    Getting started, English
Primeiros-Passos.md   Getting started, Portuguese (Brazil)
Primeros-Pasos.md     Getting started, Spanish
_Sidebar.md           the sidebar every page shows
images/               the screenshots, one per language, and the icon
```

A page's file name is its address: `Getting-Started.md` is `/wiki/Getting-Started`,
which is what the links between the pages use. Images are referenced by their
full raw URL (`raw.githubusercontent.com/wiki/…`), the one form that renders
both in the wiki and in a preview of these files here. `README.md` is not a page
and is not published.

This folder is for players. Anything about building or bundling belongs in
[docs/](../docs/), and anything a reader needs before downloading belongs in the
[README](../README.md).
