// RSS-pandoc-Typst-template — zakelijke, rustige enterprise-stijl.
// Gebruikt door tools/Build-Documentation.ps1; variabelen komen uit de
// YAML-metadata van de canonical Markdown-bronnen.

#let accent = rgb("#0F4761")          // rustig donkerblauw (koppen, kaders) — zelfde als DOCX-reference-thema
#let accent-light = rgb("#E8F0F7")    // codeachtergrond
#let warn-bg = rgb("#FBF1E6")         // callout-achtergrond
#let warn-edge = rgb("#C57A2B")       // callout-rand (amber)
#let text-gray = rgb("#333333")
#let rule-gray = rgb("#C8D2DC")

#set page(
  paper: "a4",
  margin: (top: 2.4cm, bottom: 2.6cm, left: 2.2cm, right: 2.2cm),
  header: context {
    if counter(page).get().first() > 1 {
      set text(size: 8pt, fill: text-gray)
      grid(columns: (1fr, auto),
        align(left, [$title$]),
        align(right, [$subtitle-short$]),
      )
      v(2pt)
      line(length: 100%, stroke: 0.5pt + rule-gray)
    }
  },
  footer: context {
    set text(size: 8pt, fill: text-gray)
    line(length: 100%, stroke: 0.5pt + rule-gray)
    v(2pt)
    grid(columns: (1fr, auto, 1fr),
      align(left, [$title-short$]),
      align(center, [Pagina #context counter(page).display() van #counter(page).final().first()]),
      align(right, [$classification$]),
    )
  },
)

#set text(font: "DejaVu Sans", size: 9.5pt, fill: text-gray, lang: "nl", hyphenate: true)
#set par(justify: true, leading: 0.62em)

#show heading.where(level: 1): it => {
  v(10pt)
  set text(size: 15pt, fill: accent, weight: "bold")
  block(below: 10pt, it)
  v(-4pt)
  line(length: 100%, stroke: 1pt + accent)
  v(6pt)
}
#show heading.where(level: 2): it => {
  set text(size: 12pt, fill: accent, weight: "bold")
  block(above: 12pt, below: 6pt, it)
}
#show heading.where(level: 3): it => {
  set text(size: 10.5pt, fill: text-gray, weight: "bold")
  block(above: 10pt, below: 4pt, it)
}

#show raw.where(block: true): it => block(
  fill: accent-light,
  stroke: 0.5pt + rule-gray,
  inset: 8pt,
  radius: 3pt,
  width: 100%,
  text(size: 8.2pt, it),
)
#show raw.where(block: false): it => box(
  fill: accent-light,
  inset: (x: 3pt, y: 0pt),
  radius: 2pt,
  text(font: "DejaVu Sans Mono", size: 8.6pt, fill: rgb("#204A6B"), it),
)

// pandoc zet blockquotes om in #quote[...]: stijl als WARN/NOTE-callout
#show quote: it => block(
  fill: warn-bg,
  stroke: (left: 2.5pt + warn-edge),
  inset: 10pt,
  radius: (right: 3pt),
  width: 100%,
  breakable: true,
  it,
)

#show table: it => {
  set text(size: 8.6pt)
  it
}
// grote tabellen mogen over paginagrenzen breken
#show figure: set block(breakable: true)
#set table(
  stroke: 0.5pt + rule-gray,
  inset: 5pt,
  fill: (x, y) => if y == 0 { accent-light },
)

#set document(title: "$title$", author: "$audience$")

// ------------------------------------------------------------- voorpagina
#align(center)[
  #v(4.2cm)
  #text(size: 24pt, fill: accent, weight: "bold")[$title$]
  #v(6pt)
  #text(size: 12pt, fill: text-gray)[$subtitle$]
  #v(4pt)
  #text(size: 9pt, fill: text-gray)[RSS — Surface Deployment Stick · Windows 11-deployment voor Surface Laptop]
  #v(2.6cm)
  #table(
    columns: (auto, auto),
    align: (right, left),
    inset: (x: 14pt, y: 5pt),
    stroke: none,
    fill: none,
    text(weight: "bold")[Documentversie], [$version$],
    text(weight: "bold")[Datum], [$docdate$],
    text(weight: "bold")[Doelgroep], [$audience$],
    text(weight: "bold")[Classificatie], [$classification$],
    text(weight: "bold")[Gegenereerd uit], [docs/source/ + config/sources.json],
  )
  #v(4pt)
  #line(length: 58%, stroke: 1pt + accent)
  #v(2.4cm)
  #text(size: 8.5pt, fill: text-gray)[Source-available beheerdocument — geen opensourcelicentie. #linebreak() Deze PDF is gegenereerd; wijzig de bron in docs/source en herbouw met tools/Build-Documentation.ps1.]
]
#pagebreak()

// --------------------------------------------------------- inhoudsopgave
#outline(title: [Inhoudsopgave], depth: 2, indent: 1em)
#pagebreak()

// ------------------------------------------------------------------ body
$body$
