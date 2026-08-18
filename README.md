# ICA WGS Delivery Pipeline

Diese Nextflow-Pipeline sammelt kleine Ergebnisdateien aus einem WGS-Lauf in
einer zentralen Delivery-Struktur. Sie übernimmt ausschließlich:

- `.vcf` und `.vcf.gz`
- `.tsv` und `.tsv.gz`
- `.csv` und `.csv.gz`

Große Alignment-Dateien wie BAM, CRAM und deren Indizes werden nicht als
Prozess-Input ausgewählt und nicht in den Delivery-Ordner kopiert.

## Zielstruktur

Der in ICA gewählte Analyse-Outputordner ist zugleich der Ordner, den der
Download Connector überwachen soll:

```text
<connector-root>/
├── production/
│   └── wgs/
│       └── <run_name>/
│           ├── delivery_manifest.tsv
│           └── <beibehaltene Unterstruktur aus dem WGS-Output>/
│               ├── variants.vcf.gz
│               └── metrics.tsv
└── test/
    └── wgs/
        └── <run_name>/
```

Später können weitere Sammelpipelines mit `--category qc`, `wes` oder `panel`
denselben zentralen Outputordner verwenden.

## Parameter

| Parameter | Pflicht | Standard | Bedeutung |
|---|---:|---|---|
| `--input_dir` | ja | – | Ergebnisordner des WGS-Laufs in ICA |
| `--run_name` | ja | – | Eindeutiger Laufname, z. B. `OW77` |
| `--delivery_root` | nein | `production` | Zielbereich `production` oder `test` |
| `--category` | nein | `wgs` | Oberster Delivery-Unterordner |
| `--outdir` | nein | `out` | Pipeline-Output; in ICA normalerweise `out` belassen |

`run_name`, `delivery_root` und `category` dürfen Buchstaben, Zahlen, Punkt,
Unterstrich und Bindestrich enthalten. Bereits vorhandene Zieldateien werden
absichtlich nicht überschrieben (`overwrite: false`). So fällt eine doppelte
Verwendung desselben Laufnamens auf, statt alte Ergebnisse still zu ersetzen.

## Lokaler Test

```bash
nextflow run main.nf \
  --input_dir /pfad/zum/wgs-output \
  --run_name OW77 \
  --delivery_root test \
  --outdir test-delivery
```

## Einrichtung in ICA

1. Unter **Flow > Pipelines > Create > Nextflow > JSON-based** eine Pipeline
   anlegen.
2. `main.nf` als Pipeline-Code und `nextflow.config` als Konfiguration einfügen.
3. Im Reiter der Input-Form-Dateien den Inhalt von `inputForm.json` übernehmen.
   Das Formular zeigt einen ICA-Ordner, den Laufnamen und ein Dropdown für
   Produktion oder Test an. `category=wgs` und `outdir=out` bleiben intern.
4. Mit **Simulate** prüfen, dass alle drei Felder korrekt dargestellt werden.
5. Beim Start als Analyse-Output immer denselben zentralen ICA-Projektordner
   auswählen.
6. Den Download Connector auf genau diesen zentralen Projektordner richten.

ICA übernimmt den Inhalt von `out` in den beim Analysestart ausgewählten
Outputordner. Deshalb bleibt `--outdir out`; die Pipeline erzeugt darunter die
Struktur `<delivery_root>/wgs/<run_name>/...`.

## Manifest

`delivery_manifest.tsv` enthält für jede kopierte Datei:

- relativen Pfad im WGS-Quellordner,
- relativen Pfad im Delivery-Ordner,
- Dateigröße in Bytes.

Damit lässt sich nach dem Connector-Download automatisiert prüfen, ob alle
ausgewählten Dateien angekommen sind.

## Bewusste Grenzen

- Versteckte Dateien und versteckte Verzeichnisse werden ignoriert.
- Symlinks werden verfolgt; kopiert wird der Dateiinhalt, nicht der Link.
- Die Pipeline filtert nach Dateiendung, nicht nach Dateigröße. Falls einzelne
  VCF-Dateien ebenfalls ausgeschlossen werden sollen, sollte zusätzlich eine
  explizite Größenobergrenze ergänzt werden.
