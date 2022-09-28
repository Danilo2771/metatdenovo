//
// Run EUKULELE on protein fasta from orf_caller output
//

include { EUKULELE      } from '../../modules/local/eukulele/main'
//include { MV_DIR        } from '../../modules/local/mvdir'
include { EUKULELE_DB   } from '../../modules/local/eukulele/download'
include { FORMAT_TAX    } from '../../modules/local/format_tax'

workflow SUB_EUKULELE {

    take:
        fastaprot

    main:
        ch_versions = Channel.empty()

        //MV_DIR(fastaprot)

        String directoryName = params.eukulele_dbpath
        File directory = new File(directoryName)

        if(! directory.exists()){
            directory.mkdir()
            EUKULELE_DB( )
            if ( params.eukulele_db == 'mmetsp' ) {
                EUKULELE(MV_DIR.out.contigs_dir, EUKULELE_DB.out.mmetsp_db)
                FORMAT_TAX(EUKULELE.out.taxonomy_estimation.map { it[1] } )
            } else
                EUKULELE(MV_DIR.out.contigs_dir, EUKULELE_DB.out.phylo_db)
                FORMAT_TAX(EUKULELE.out.taxonomy_estimation.map { it[1] } )
        } else {
                ch_database = Channel.fromPath(params.eukulele_dbpath)
                EUKULELE(fastaprot, ch_database)
                FORMAT_TAX(EUKULELE.out.taxonomy_estimation.map { it[1] } )
        }

    emit:
        taxonomy_estimation = EUKULELE.out.taxonomy_estimation
        taxonomy_counts     = EUKULELE.out.taxonomy_counts
        diamond             = EUKULELE.out.diamond

        versions            = EUKULELE.out.versions
}