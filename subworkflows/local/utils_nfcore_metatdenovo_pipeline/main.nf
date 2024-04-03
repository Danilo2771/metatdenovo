//
// Subworkflow with functionality specific to the nf-core/metatdenovo pipeline
//
import groovy.json.JsonSlurper

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFVALIDATION_PLUGIN } from '../../nf-core/utils_nfvalidation_plugin'
include { paramsSummaryMap          } from 'plugin/nf-validation'
include { fromSamplesheet           } from 'plugin/nf-validation'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'
include { completionEmail           } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { dashedLine                } from '../../nf-core/utils_nfcore_pipeline'
include { nfCoreLogo                } from '../../nf-core/utils_nfcore_pipeline'
include { imNotification            } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { workflowCitation          } from '../../nf-core/utils_nfcore_pipeline'

/*
========================================================================================
    SUBWORKFLOW TO INITIALISE PIPELINE
========================================================================================
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    help              // boolean: Display help text
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args  //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved

    main:

    ch_versions = Channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //
    pre_help_text = nfCoreLogo(monochrome_logs)
    post_help_text = '\n' + workflowCitation() + '\n' + dashedLine(monochrome_logs)
    def String workflow_command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"

    UTILS_NFVALIDATION_PLUGIN (
        help,
        workflow_command,
        pre_help_text,
        post_help_text,
        validate_params,
        "nextflow_schema.json"
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )

}

/*
========================================================================================
    SUBWORKFLOW FOR PIPELINE COMPLETION
========================================================================================
*/

workflow PIPELINE_COMPLETION {

    take:
    email           //  string: email address
    email_on_fail   //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    hook_url        //  string: hook URL for notifications
    multiqc_report  //  string: Path to MultiQC report

    main:

    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(summary_params, email, email_on_fail, plaintext_email, outdir, monochrome_logs, multiqc_report.toList())
        }

        completionSummary(monochrome_logs)

        if (hook_url) {
            imNotification(summary_params, hook_url)
        }
    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs: https://nf-co.re/docs/usage/troubleshooting"
    }

}

/*
========================================================================================
    FUNCTIONS
========================================================================================
*/

def validateInputSamplesheet(input) {
    def (metas, fastqs) = input[1..2]

    // Check that multiple runs of the same sample are of the same strandedness
    def strandedness_ok = metas.collect{ it.strandedness }.unique().size == 1
    if (!strandedness_ok) {
        error("Please check input samplesheet -> Multiple runs of a sample must have the same strandedness!: ${metas[0].id}")
    }

    // Check that multiple runs of the same sample are of the same datatype i.e. single-end / paired-end
    def endedness_ok = metas.collect{ it.single_end }.unique().size == 1
    if (!endedness_ok) {
        error("Please check input samplesheet -> Multiple runs of a sample must be of the same datatype i.e. single-end or paired-end: ${metas[0].id}")
    }

    return [ metas[0], fastqs ]
}

//
// Generate methods description for MultiQC
//
def toolCitationText() {
    // TODO nf-core: Optionally add in-text citation tools to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "Tool (Foo et al. 2023)" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def citation_text = [
            "Tools used in the workflow included:",
            "FastQC (Andrews 2010),",
            "MultiQC (Ewels et al. 2016)",
            "."
        ].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    // TODO nf-core: Optionally add bibliographic entries to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "<li>Author (2023) Pub name, Journal, DOI</li>" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def reference_text = [
            "<li>Andrews S, (2010) FastQC, URL: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/).</li>",
            "<li>Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics , 32(19), 3047–3048. doi: /10.1093/bioinformatics/btw354</li>"
        ].join(' ').trim()

    return reference_text
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    meta["doi_text"] = meta.manifest_map.doi ? "(doi: <a href=\'https://doi.org/${meta.manifest_map.doi}\'>${meta.manifest_map.doi}</a>)" : ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "": "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = ""
    meta["tool_bibliography"] = ""

    // TODO nf-core: Only uncomment below if logic in toolCitationText/toolBibliographyText has been filled!
    // meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    // meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine =  new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}

//
// Print a warning if both GTF and GFF have been provided
//
def gtfGffWarn() {
    log.warn "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
        "  Both '--gtf' and '--gff' parameters have been provided.\n" +
        "  Using GTF file as priority.\n" +
        "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}

//
// Print a warning if using GRCh38 assembly from igenomes.config
//
def ncbiGenomeWarn() {
    log.warn "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
        "  When using '--genome GRCh38' the assembly is from the NCBI and NOT Ensembl.\n" +
        "  Biotype QC will be skipped to circumvent the issue below:\n" +
        "  https://github.com/nf-core/rnaseq/issues/460\n\n" +
        "  If you would like to use the soft-masked Ensembl assembly instead please see:\n" +
        "  https://github.com/nf-core/rnaseq/issues/159#issuecomment-501184312\n" +
        "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}

//
// Print a warning if using a UCSC assembly from igenomes.config
//
def ucscGenomeWarn() {
    log.warn "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
        "  When using UCSC assemblies the 'gene_biotype' field is absent from the GTF file.\n" +
        "  Biotype QC will be skipped to circumvent the issue below:\n" +
        "  https://github.com/nf-core/rnaseq/issues/460\n\n" +
        "  If you would like to use the soft-masked Ensembl assembly instead please see:\n" +
        "  https://github.com/nf-core/rnaseq/issues/159#issuecomment-501184312\n" +
        "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}


//
// Print a warning if using '--aligner star_rsem' and providing both '--rsem_index' and '--star_index'
//
def rsemStarIndexWarn() {
    log.warn "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
        "  When using '--aligner star_rsem', both the STAR and RSEM indices should\n" +
        "  be present in the path specified by '--rsem_index'.\n\n" +
        "  This warning has been generated because you have provided both\n" +
        "  '--rsem_index' and '--star_index'. The pipeline will ignore the latter.\n\n" +
        "  Please see:\n" +
        "  https://github.com/nf-core/rnaseq/issues/568\n" +
        "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}

//
// Print a warning if using '--aligner star_rsem' and providing '--star_extra_alignment_args'
//
def rsemStarExtraArgumentsWarn() {
    log.warn "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
        "  No additional arguments can be passed to STAR when using RSEM.\n" +
        "  Because RSEM enforces its own parameters for STAR, any extra arguments\n" +
        "  to STAR will be ignored. Alternatively, choose the STAR+Salmon route.\n\n" +
        "  This warning has been generated because you have provided both\n" +
        "  '--aligner star_rsem' and '--extra_star_align_args'.\n\n" +
        "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}

//
// Print a warning if using '--additional_fasta' and '--<ALIGNER>_index'
//
def additionaFastaIndexWarn(index) {
    log.warn "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
        "  When using '--additional_fasta <FASTA_FILE>' the aligner index will not\n" +
        "  be re-built with the transgenes incorporated by default since you have \n" +
        "  already provided an index via '--${index}_index <INDEX>'.\n\n" +
        "  Set '--additional_fasta <FASTA_FILE> --${index}_index false --gene_bed false --save_reference'\n" +
        "  to re-build the index with transgenes included and the index and gene BED file will be saved in\n" +
        "  'results/genome/index/${index}/' for re-use with '--${index}_index'.\n\n" +
        "  Ignore this warning if you know that the index already contains transgenes.\n\n" +
        "  Please see:\n" +
        "  https://github.com/nf-core/rnaseq/issues/556\n" +
        "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}

//
// Function to generate an error if contigs in genome fasta file > 512 Mbp
//
def checkMaxContigSize(fai_file) {
    def max_size = 512000000
    fai_file.eachLine { line ->
        def lspl  = line.split('\t')
        def chrom = lspl[0]
        def size  = lspl[1]
        if (size.toInteger() > max_size) {
            def error_string = "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
                "  Contig longer than ${max_size}bp found in reference genome!\n\n" +
                "  ${chrom}: ${size}\n\n" +
                "  Provide the '--bam_csi_index' parameter to use a CSI instead of BAI index.\n\n" +
                "  Please see:\n" +
                "  https://github.com/nf-core/rnaseq/issues/744\n" +
                "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            error(error_string)
        }
    }
}

//
// Create MultiQC tsv custom content from a list of values
//
def multiqcTsvFromList(tsv_data, header) {
    def tsv_string = ""
    if (tsv_data.size() > 0) {
        tsv_string += "${header.join('\t')}\n"
        tsv_string += tsv_data.join('\n')
    }
    return tsv_string
}

//
// Function that parses Salmon quant 'meta_info.json' output file to get inferred strandedness
//
def getSalmonInferredStrandedness(json_file) {
    def lib_type = new JsonSlurper().parseText(json_file.text).get('library_types')[0]
    def strandedness = 'reverse'
    if (lib_type) {
        if (lib_type in ['U', 'IU']) {
            strandedness = 'unstranded'
        } else if (lib_type in ['SF', 'ISF']) {
            strandedness = 'forward'
        } else if (lib_type in ['SR', 'ISR']) {
            strandedness = 'reverse'
        }
    }
    return strandedness
}

//
// Function that parses and returns the alignment rate from the STAR log output
//
def getStarPercentMapped(params, align_log) {
    def percent_aligned = 0
    def pattern = /Uniquely mapped reads %\s*\|\s*([\d\.]+)%/
    align_log.eachLine { line ->
        def matcher = line =~ pattern
        if (matcher) {
            percent_aligned = matcher[0][1].toFloat()
        }
    }

    def pass = false
    if (percent_aligned >= params.min_mapped_reads.toFloat()) {
        pass = true
    }
    return [ percent_aligned, pass ]
}

//
// Function to check whether biotype field exists in GTF file
//
def biotypeInGtf(gtf_file, biotype) {
    def hits = 0
    gtf_file.eachLine { line ->
        def attributes = line.split('\t')[-1].split()
        if (attributes.contains(biotype)) {
            hits += 1
        }
    }
    if (hits) {
        return true
    } else {
        log.warn "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
            "  Biotype attribute '${biotype}' not found in the last column of the GTF file!\n\n" +
            "  Biotype QC will be skipped to circumvent the issue below:\n" +
            "  https://github.com/nf-core/rnaseq/issues/460\n\n" +
            "  Amend '--featurecounts_group_type' to change this behaviour.\n" +
            "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        return false
    }
}

//
// Function that parses and returns the predicted strandedness from the RSeQC infer_experiment.py output
//
def getInferexperimentStrandedness(inferexperiment_file, cutoff=30) {
    def sense        = 0
    def antisense    = 0
    def undetermined = 0
    inferexperiment_file.eachLine { line ->
        def undetermined_matcher = line =~ /Fraction of reads failed to determine:\s([\d\.]+)/
        def se_sense_matcher     = line =~ /Fraction of reads explained by "\++,--":\s([\d\.]+)/
        def se_antisense_matcher = line =~ /Fraction of reads explained by "\+-,-\+":\s([\d\.]+)/
        def pe_sense_matcher     = line =~ /Fraction of reads explained by "1\++,1--,2\+-,2-\+":\s([\d\.]+)/
        def pe_antisense_matcher = line =~ /Fraction of reads explained by "1\+-,1-\+,2\+\+,2--":\s([\d\.]+)/
        if (undetermined_matcher) undetermined = undetermined_matcher[0][1].toFloat() * 100
        if (se_sense_matcher)     sense        = se_sense_matcher[0][1].toFloat() * 100
        if (se_antisense_matcher) antisense    = se_antisense_matcher[0][1].toFloat() * 100
        if (pe_sense_matcher)     sense        = pe_sense_matcher[0][1].toFloat() * 100
        if (pe_antisense_matcher) antisense    = pe_antisense_matcher[0][1].toFloat() * 100
    }
    def strandedness = 'unstranded'
    if (sense >= 100-cutoff) {
        strandedness = 'forward'
    } else if (antisense >= 100-cutoff) {
        strandedness = 'reverse'
    }
    return [ strandedness, sense, antisense, undetermined ]
}
