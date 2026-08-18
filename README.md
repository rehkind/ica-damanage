# ICA WGS Delivery Pipeline

Diese Nextflow-Pipeline sammelt relevante Ergebnisdateien aus einem
DRAGEN-WGS-Lauf in einer zentralen Delivery-Struktur. Sie übernimmt:

- `.vcf` und `.vcf.gz`
- `.tsv` und `.tsv.gz`
- `.csv` und `.csv.gz`
- `summary.json` und `passfail.json` auf der obersten Ebene
- den vollständigen Ordner `reports/` einschließlich HTML, CSS und Bildern

Große Alignment-Dateien wie BAM, CRAM und deren Indizes werden nicht als
Prozess-Input ausgewählt und nicht in den Delivery-Ordner kopiert. Der Ordner
`ica_logs/` wird vollständig ignoriert.

## Zielstruktur

Der in ICA gewählte Analyse-Outputordner ist zugleich der Ordner, den der
Download Connector überwachen soll:

```text
<connector-root>/
├── production/
│   └── wgs/
│       └── <run_name>/
│           ├── delivery_manifest.tsv
│           ├── summary.json
│           ├── passfail.json
│           ├── tumor-fastq-list-1.csv
│           ├── fastq-list-1.csv
│           ├── reports/
│           │   └── ...
│           └── <sample>/
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
| `--category` | verborgen | `wgs` | Pipeline-Kategorie unterhalb des Zielbereichs |
| `--outdir` | verborgen | `out` | ICA-interner Pipeline-Output |

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

## Einrichtung als Git-Pipeline in ICA

1. Unter **Flow > Pipelines > Create > Nextflow > From Git** eine Pipeline
   anlegen und Repository-URL sowie Commit-ID eintragen.
2. Als Schema-Datei `nextflow_schema.json` angeben.
3. Prüfen, dass `input_dir` als Verzeichnispfad, `run_name` als Textfeld und
   `delivery_root` als Auswahl mit `production` und `test` dargestellt werden.
   `category=wgs` und `outdir=out` sind verborgen.
4. Beim Start als Analysis Output Folder immer denselben zentralen
   ICA-Projektordner, beispielsweise `/Output`, auswählen.
5. Den Download Connector auf genau diesen zentralen Projektordner richten.

ICA übernimmt den Inhalt von `out` in den beim Analysestart ausgewählten
Outputordner. Deshalb ist `/Output` **nicht** der Wert von `delivery_root`.
Die Pipeline erzeugt unter dem ICA-Outputordner die Struktur
`<delivery_root>/wgs/<run_name>/...`.

## Manifest

`delivery_manifest.tsv` enthält für jede kopierte Datei:

- relativen Pfad im WGS-Quellordner,
- relativen Pfad im Delivery-Ordner,
- Dateigröße in Bytes.

Damit lässt sich nach dem Connector-Download automatisiert prüfen, ob alle
ausgewählten Dateien angekommen sind.

## Debug-Ausgaben

Das Nextflow-Log enthält Meldungen mit dem Präfix `[ica-wgs-delivery]`:

- `START` und alle wirksamen Parameter,
- `SELECT` für jede vom Filter ausgewählte Datei,
- `COPIED` nach erfolgreichem Abschluss des jeweiligen Copy-Prozesses,
- `MANIFEST` mit der Anzahl der aufgenommenen Dateien,
- `FINISH` mit Status, Dauer und gegebenenfalls der Fehlermeldung.

Jeder Copy-Task meldet außerdem Start und Abschluss in seiner Standardausgabe;
der zugehörige relative Pfad steht im Nextflow-Task-Tag.
Wenn nach `Scanning input directory` keine `SELECT`-Meldung erscheint, wurde
entweder ein falscher beziehungsweise leerer Eingabeordner übergeben oder keine
Datei entspricht den Auswahlregeln.

## Bewusste Grenzen

- Versteckte Dateien und versteckte Verzeichnisse werden ignoriert.
- Symlinks werden verfolgt; kopiert wird der Dateiinhalt, nicht der Link.
- Außerhalb von `reports/` filtert die Pipeline nach Dateiname beziehungsweise
  Dateiendung, nicht nach Dateigröße. Falls einzelne VCF-Dateien ebenfalls
  ausgeschlossen werden sollen, kann zusätzlich eine Größenobergrenze ergänzt
  werden.
