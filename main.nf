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

params.input_dir = ''
params.outdir    = 'out'
params.delivery_root = 'production'
params.category  = 'wgs'
params.run_name  = ''

def isSelectedResult(String relativePath) {
    def normalized = relativePath.replace('\\', '/')
    def parts = normalized.tokenize('/')
    def filename = parts[-1].toLowerCase()

    // ICA execution logs are not part of the scientific delivery.
    if (parts[0] == 'ica_logs') {
        return false
    }

    // The complete DRAGEN HTML report, including its assets, is retained.
    if (parts[0] == 'reports') {
        return true
    }

    // Only the two useful DRAGEN run summaries are retained as JSON.
    if (parts.size() == 1 && filename in ['summary.json', 'passfail.json']) {
        return true
    }

    return filename ==~ /.*\.(vcf|tsv|csv)(\.gz)?$/
}

process COPY_SELECTED_FILE {
    container 'public.ecr.aws/lts/ubuntu:22.04'

    tag "${relative_path}"

    publishDir {
        def parent = relative_path.contains('/')
            ? relative_path.substring(0, relative_path.lastIndexOf('/'))
            : ''
        "${params.outdir}/${params.delivery_root}/${params.category}/${params.run_name}${parent ? '/' + parent : ''}"
    }, mode: 'copy', overwrite: false, saveAs: { filename -> filename.tokenize('/')[-1] }

    input:
    tuple val(relative_path), val(source_size), path(source_file)

    output:
    tuple val(relative_path), val(source_size), path('selected/*'), emit: copied

    script:
    """
    echo '[ica-wgs-delivery] COPY task started'
    mkdir -p selected
    cp -L -- "${source_file}" selected/
    echo '[ica-wgs-delivery] COPY task completed'
    """
}

process WRITE_MANIFEST {
    container 'public.ecr.aws/lts/ubuntu:22.04'

    tag "${params.delivery_root}/${params.category}/${params.run_name}"

    publishDir "${params.outdir}/${params.delivery_root}/${params.category}/${params.run_name}",
        mode: 'copy', overwrite: false

    input:
    val copied_files

    output:
    path 'delivery_manifest.tsv'

    script:
    def fileCount = copied_files.size()
    def rows = copied_files
        .sort { a, b -> a[0] <=> b[0] }
        .collect { row ->
            def relative = row[0]
            def size = row[1]
            "${relative}\t${params.delivery_root}/${params.category}/${params.run_name}/${relative}\t${size}"
        }
        .join('\n')

    """
    echo '[ica-wgs-delivery] MANIFEST files=${fileCount}'
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

    log.info "[ica-wgs-delivery] START"
    log.info "[ica-wgs-delivery] input_dir=${inputRoot}"
    log.info "[ica-wgs-delivery] run_name=${params.run_name}"
    log.info "[ica-wgs-delivery] delivery_root=${params.delivery_root}"
    log.info "[ica-wgs-delivery] category=${params.category}"
    log.info "[ica-wgs-delivery] outdir=${params.outdir}"
    log.info "[ica-wgs-delivery] target=${params.outdir}/${params.delivery_root}/${params.category}/${params.run_name}"
    log.info "[ica-wgs-delivery] Scanning input directory"

    selected = Channel
        // Enumerating a path does not stage it. Only files surviving the
        // filter below are passed to COPY_SELECTED_FILE and transferred.
        .fromPath("${inputText}/**/*",
                  type: 'file', hidden: false, followLinks: true, checkIfExists: false)
        .map { source ->
            def absolute = source.toAbsolutePath().normalize()
            def relative = inputRoot.relativize(absolute).toString().replace('\\', '/')
            tuple(relative, source)
        }
        .filter { relative, source -> isSelectedResult(relative) }
        .map { relative, source ->
            def size = source.size()
            log.info "[ica-wgs-delivery] SELECT ${relative} (${size} bytes)"
            tuple(relative, size, source)
        }
        .ifEmpty {
            error "No delivery files found below: ${inputText}"
        }

    COPY_SELECTED_FILE(selected)
    copied_for_manifest = COPY_SELECTED_FILE.out.copied.map { rel, size, copied ->
        log.info "[ica-wgs-delivery] COPIED ${rel} (${size} bytes)"
        tuple(rel, size)
    }
    WRITE_MANIFEST(copied_for_manifest.collect())
}

workflow.onComplete {
    log.info "[ica-wgs-delivery] FINISH status=${workflow.success ? 'SUCCESS' : 'FAILED'}"
    log.info "[ica-wgs-delivery] duration=${workflow.duration}"
    if (workflow.errorMessage) {
        log.error "[ica-wgs-delivery] error=${workflow.errorMessage}"
    }
}
