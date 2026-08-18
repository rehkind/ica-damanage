nextflow.enable.dsl = 2

/*
 * Collect small, review-relevant result files from an ICA analysis without
 * staging BAM/CRAM files. The directory structure below the source folder is
 * retained in the delivery tree.
 */

def requireText(value, name) {
    def text = value?.toString()?.trim()
    if (!text) {
        error "Missing required parameter: --${name}"
    }
    return text
}

def safePathPart(value, name) {
    def text = requireText(value, name)
    if (!(text ==~ /[A-Za-z0-9][A-Za-z0-9._-]*/)) {
        error "--${name} may contain only letters, numbers, '.', '_' and '-'"
    }
    return text
}

params.input_dir = null
params.outdir    = 'out'
params.delivery_root = 'production'
params.category  = 'wgs'
params.run_name  = null

process COPY_SELECTED_FILE {
    tag relative_path

    publishDir {
        def parent = relative_path.contains('/')
            ? relative_path.substring(0, relative_path.lastIndexOf('/'))
            : ''
        "${params.outdir}/${params.delivery_root}/${params.category}/${params.run_name}${parent ? '/' + parent : ''}"
    }, mode: 'copy', overwrite: false, saveAs: { selected_file.name }

    input:
    tuple val(relative_path), path(source_file)

    output:
    tuple val(relative_path), val(source_file.size()), path("selected/${source_file.name}"), emit: copied

    script:
    """
    mkdir -p selected
    cp -L -- "${source_file}" "selected/${source_file.name}"
    """
}

process WRITE_MANIFEST {
    tag "${params.delivery_root}/${params.category}/${params.run_name}"

    publishDir "${params.outdir}/${params.delivery_root}/${params.category}/${params.run_name}",
        mode: 'copy', overwrite: false

    input:
    val copied_files

    output:
    path 'delivery_manifest.tsv'

    script:
    def rows = copied_files
        .sort { a, b -> a[0] <=> b[0] }
        .collect { row ->
            def relative = row[0]
            def size = row[1]
            "${relative}\t${params.delivery_root}/${params.category}/${params.run_name}/${relative}\t${size}"
        }
        .join('\n')

    """
    printf '%s\n' 'source_relative_path\tdelivery_relative_path\tsize_bytes' > delivery_manifest.tsv
    cat >> delivery_manifest.tsv <<'MANIFEST_ROWS'
    ${rows}
    MANIFEST_ROWS
    """
}

workflow {
    def inputText = requireText(params.input_dir, 'input_dir')
    params.delivery_root = safePathPart(params.delivery_root, 'delivery_root')
    params.category = safePathPart(params.category, 'category')
    params.run_name = safePathPart(params.run_name, 'run_name')

    def inputRoot = file(inputText, checkIfExists: true).toAbsolutePath().normalize()
    if (!inputRoot.isDirectory()) {
        error "--input_dir must point to a directory: ${inputText}"
    }

    selected = Channel
        .fromPath("${inputText}/**/*.{vcf,vcf.gz,tsv,tsv.gz,csv,csv.gz}",
                  type: 'file', hidden: false, followLinks: true, checkIfExists: false)
        .map { source ->
            def absolute = source.toAbsolutePath().normalize()
            def relative = inputRoot.relativize(absolute).toString().replace('\\', '/')
            tuple(relative, source)
        }
        .ifEmpty {
            error "No VCF/TSV/CSV files found below: ${inputText}"
        }

    COPY_SELECTED_FILE(selected)
    WRITE_MANIFEST(COPY_SELECTED_FILE.out.copied.map { rel, size, copied -> tuple(rel, size) }.collect())
}
