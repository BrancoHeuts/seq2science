def get_reads(wildcards):
    """
    Function that returns the reads for any aligner.
    """
    if sampledict[wildcards.sample]["layout"] == "SINGLE":
        return expand("{trimmed_dir}/{{sample}}_trimmed.{fqsuffix}.gz", **config)
    return sorted(expand("{trimmed_dir}/{{sample}}_{fqext}_trimmed.{fqsuffix}.gz", **config))


if config["aligner"] == "bowtie2":

    rule bowtie2_index:
        """
        Make a genome index for bowtie2. This index is required for alignment.
        """
        input:
            expand("{genome_dir}/{{assembly}}/{{assembly}}.fa", **config),
        output:
            directory(expand("{genome_dir}/{{assembly}}/index/{aligner}/", **config)),
        log:
            expand("{log_dir}/{aligner}_index/{{assembly}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_index/{{assembly}}.benchmark.txt", **config)[0]
        priority: 1
        threads: 4
        conda:
            "../envs/bowtie2.yaml"
        params:
            config["index"],
        shell:
            """
            bowtie2-build {params} --threads {threads} {input} {output}/{wildcards.assembly} > {log} 2>&1
            """

    rule bowtie2_align:
        """
        Align reads against a genome (index) with bowtie2, and pipe the output to the required sorter(s).
        """
        input:
            reads=get_reads,
            index=expand("{genome_dir}/{{assembly}}/index/{aligner}/", **config)
        output:
            pipe(expand("{result_dir}/{aligner}/{{assembly}}-{{sample}}.samtools-coordinate.pipe", **config)[0]),
        log:
            expand("{log_dir}/{aligner}_align/{{assembly}}-{{sample}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_align/{{assembly}}-{{sample}}.benchmark.txt", **config)[0]
        message: explain_rule(f"{config['aligner']}_align")
        params:
            input=(
                lambda wildcards, input: ["-U", input.reads]
                if sampledict[wildcards.sample]["layout"] == "SINGLE"
                else ["-1", input.reads[0], "-2", input.reads[1]]
            ),
            params=config["align"],
        priority: 0
        threads: 9
        conda:
            "../envs/bowtie2.yaml"
        shell:
            """
            bowtie2 {params.params} --threads {threads} -x {input.index}{wildcards.assembly} {params.input} 2> {log} | tee {output} 1> /dev/null 2>> {log}
            """


elif config["aligner"] == "bwa-mem":

    rule bwa_index:
        """
        Make a genome index for bwa (mem). This index is required for alignment.
        """
        input:
            expand("{genome_dir}/{{assembly}}/{{assembly}}.fa", **config),
        output:
            directory(expand("{genome_dir}/{{assembly}}/index/{aligner}/", **config)),
        log:
            expand("{log_dir}/{aligner}_index/{{assembly}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_index/{{assembly}}.benchmark.txt", **config)[0]
        params:
            prefix="{genome_dir}/{{assembly}}/index/{aligner}/{{assembly}}".format(**config),
            params=config["index"],
        priority: 1
        resources:
            mem_gb=5,
        conda:
            "../envs/bwa.yaml"
        shell:
            """
            bwa index -p {params.prefix} {params.params} {input} > {log} 2>&1
            """

    rule bwa_mem:
        """
        Align reads against a genome (index) with bwa-mem, and pipe the output to the required sorter(s).
        """
        input:
            reads=get_reads,
            index=expand("{genome_dir}/{{assembly}}/index/{aligner}/", **config)
        output:
            pipe(expand("{result_dir}/{aligner}/{{assembly}}-{{sample}}.samtools-coordinate.pipe", **config)[0]),
        log:
            expand("{log_dir}/{aligner}_align/{{assembly}}-{{sample}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_align/{{assembly}}-{{sample}}.benchmark.txt", **config)[0]
        message: explain_rule(f"{config['aligner']}_align")
        params:
            index_dir=expand("{genome_dir}/{{assembly}}/index/{aligner}/{{assembly}}", **config),
            params=config["align"],
        resources:
            mem_gb=13,
        priority: 0
        threads: 10
        conda:
            "../envs/bwa.yaml"
        shell:
            """
            bwa mem {params.params} -t {threads} {params.index_dir} {input.reads} 2> {log} | tee {output} 1> /dev/null 2>> {log}
            """

elif config["aligner"] == "bwa-mem2":

    rule bwa_mem2_index:
        """
        Make a genome index for bwa-mem2. This index is required for alignment.
        """
        input:
            expand("{genome_dir}/{{assembly}}/{{assembly}}.fa", **config),
        output:
            directory(expand("{genome_dir}/{{assembly}}/index/{aligner}/", **config)),
        log:
            expand("{log_dir}/{aligner}_index/{{assembly}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_index/{{assembly}}.benchmark.txt", **config)[0]
        params:
            prefix="{genome_dir}/{{assembly}}/index/{aligner}/{{assembly}}".format(**config)
        priority: 1
        resources:
            mem_gb=100,
        conda:
            "../envs/bwamem2.yaml"
        shell:
            """
            bwa-mem2 index -p {params.prefix} {input} > {log} 2>&1
            """

    rule bwa_mem2:
        """
        Align reads against a genome (index) with bwa-mem2, and pipe the output to the required sorter(s).
        """
        input:
            reads=get_reads,
            index=expand("{genome_dir}/{{assembly}}/index/{aligner}/", **config)
        output:
            pipe(expand("{result_dir}/{aligner}/{{assembly}}-{{sample}}.samtools-coordinate.pipe", **config)[0]),
        log:
            expand("{log_dir}/{aligner}_align/{{assembly}}-{{sample}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_align/{{assembly}}-{{sample}}.benchmark.txt", **config)[0]
        message: explain_rule(f"{config['aligner']}_align")
        params:
            index_dir=expand("{genome_dir}/{{assembly}}/index/{aligner}/{{assembly}}", **config),
            params=config["align"],
        resources:
            mem_gb=13,
        priority: 0
        threads: 10
        conda:
            "../envs/bwamem2.yaml"
        shell:
            """
            bwa-mem2 mem {params.params} -t {threads} {params.index_dir} {input.reads} 2> {log} | tee {output} 1> /dev/null 2>> {log}
            """


elif config["aligner"] == "hisat2":

    rule hisat2_splice_aware_index:
        """
        Make an exon-junction and splice aware index for hisat2. 
        This index is required for alignment and quantification of RNA-seq data.
        """
        input:
            fasta=expand("{genome_dir}/{{assembly}}/{{assembly}}.fa", **config),
            gtf=expand("{genome_dir}/{{assembly}}/{{assembly}}.annotation.gtf", **config),
        output:
            directory(expand("{genome_dir}/{{assembly}}/index/{aligner}_splice_aware/", **config)),
        log:
            expand("{log_dir}/{aligner}_index/{{assembly}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_index/{{assembly}}.benchmark.txt", **config)[0]
        message: explain_rule("hisat_splice_aware")
        priority: 1
        threads: 8
        resources:
            mem_gb=200,  # yes really
        conda:
            "../envs/hisat2.yaml"
        params:
            config["index"],
        shell:
            """
            hp=$(which hisat2)
            python3 ${{hp}}_extract_splice_sites.py {input.gtf} > {output}/splice_sites.tsv
            python3 ${{hp}}_extract_exons.py {input.gtf} > {output}/exons.tsv
            
            hisat2-build {params} -p {threads} --ss {output}/splice_sites.tsv --exon {output}/exons.tsv \
            {input.fasta} {output}/part > {log} 2>&1
            """

    rule hisat2_index:
        """
        Make a genome index for hisat2. This index is required for alignment.
        """
        input:
            expand("{genome_dir}/{{assembly}}/{{assembly}}.fa", **config),
        output:
            directory(expand("{genome_dir}/{{assembly}}/index/{aligner}/", **config)),
        log:
            expand("{log_dir}/{aligner}_index/{{assembly}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_index/{{assembly}}.benchmark.txt", **config)[0]
        priority: 1
        threads: 4
        resources:
            mem_gb=8,
        conda:
            "../envs/hisat2.yaml"
        params:
            config["index"],
        shell:
            """
            hisat2-build {params} -p {threads} {input} {output}/part > {log} 2>&1
            """

    def get_hisat_index(wildcards):
        index = "{genome_dir}/{{assembly}}/index/{aligner}/"
        if "rna_seq" in get_workflow():
            index = index[:-1] + "_splice_aware/"
        return expand(index, **config)

    rule hisat2_align:
        """
        Align reads against a genome (index) with hisat2, and pipe the output to the required sorter(s).
        """
        input:
            reads=get_reads,
            index=get_hisat_index
        output:
            pipe(expand("{result_dir}/{aligner}/{{assembly}}-{{sample}}.samtools-coordinate.pipe", **config)[0]),
        log:
            expand("{log_dir}/{aligner}_align/{{assembly}}-{{sample}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_align/{{assembly}}-{{sample}}.benchmark.txt", **config)[0]
        message: explain_rule(f"{config['aligner']}_align")
        params:
            input=(
                lambda wildcards, input: ["-U", input.reads]
                if sampledict[wildcards.sample]["layout"] == "SINGLE"
                else ["-1", input.reads[0], "-2", input.reads[1]]
            ),
            params=config["align"],
        priority: 0
        threads: 9
        conda:
            "../envs/hisat2.yaml"
        shell:
            """
            hisat2 {params.params} --threads {threads} -x {input.index}/part {params.input} 2> {log} | tee {output} 1> /dev/null 2>> {log}
            """


elif config["aligner"] == "minimap2":

    rule minimap2_index:
        """
        Make a genome index for minimap2. This index is required for alignment.
        """
        input:
            genome=expand("{genome_dir}/{{assembly}}/{{assembly}}.fa", **config),
        output:
            expand("{genome_dir}/{{assembly}}/index/{aligner}/ref.mmi", **config),
        log:
            expand("{log_dir}/{aligner}_index/{{assembly}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_index/{{assembly}}.benchmark.txt", **config)[0]
        params:
            config["index"],
        priority: 1
        threads: 3
        resources:
            mem_gb=12,
        conda:
            "../envs/minimap2.yaml"
        shell:
            """
            minimap2 -t {threads} -d {output} {input} {params} > {log} 2>&1
            """


    rule minimap2_align:
        """
        Align reads against a genome (index) with minimap2, and pipe the output to the required sorter(s).
        """
        input:
            reads=get_reads,
            index=rules.minimap2_index.output
        output:
            pipe(expand("{result_dir}/{aligner}/{{assembly}}-{{sample}}.samtools-coordinate.pipe", **config)[0]),
        log:
            expand("{log_dir}/{aligner}_align/{{assembly}}-{{sample}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_align/{{assembly}}-{{sample}}.benchmark.txt", **config)[0]
        message: explain_rule(f"{config['aligner']}_align")
        params:
        #     input=lambda wildcards, input: input.reads if config["layout"][wildcards.sample] == "SINGLE" else input.reads[0:2],
            params=config["align"],
        priority: 0
        threads: 10
        resources:
            mem_gb=20,
        conda:
            "../envs/minimap2.yaml"
        shell:
            """
            minimap2 -t {threads} -a {input.index} {input.reads} {params} > {output} 2> {log}
            """


elif config["aligner"] == "star":

    rule star_index:
        """
        Make a genome index for STAR.

        Troubleshooting:
        1) sufficient RAM & disk space?
        2) increase the RAM available (--limitGenomeGenerateRAM)
        3) reduce the number of threads (seq2science -j 5)
        4) reduce accuracy (--genomeSAsparseD 2)

        In your config.yaml:
        aligner:
            star:
                index: --limitGenomeGenerateRAM 60000000000 --genomeSAsparseD 1
        """
        input:
            genome=expand("{genome_dir}/{{assembly}}/{{assembly}}.fa", **config),
            sizefile=expand("{genome_dir}/{{assembly}}/{{assembly}}.fa.sizes", **config),
            gtf=expand("{genome_dir}/{{assembly}}/{{assembly}}.annotation.gtf", **config),
        output:
            directory(expand("{genome_dir}/{{assembly}}/index/{aligner}/", **config)),
        log:
            expand("{log_dir}/{aligner}_index/{{assembly}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_index/{{assembly}}.benchmark.txt", **config)[0]
        params:
            config["index"],
        priority: 1
        threads: 10
        resources:
            mem_gb=37,
        conda:
            "../envs/star.yaml"
        shell:
            """
            function log2 {{
                    local x=0
                    for (( y=$1-1 ; $y > 0; y >>= 1 )) ; do
                        let x=$x+1
                    done
                    echo $x
            }}

            # set genome dependent variables
            NBits=""
            NBases=""
            GenomeLength=$(awk -F"\t" '{{x+=$2}}END{{printf "%i", x}}' {input.sizefile})
            NumberOfReferences=$(awk 'END{{print NR}}' {input.sizefile})
            if [ $NumberOfReferences -gt 5000 ]; then
                # for large genomes, --genomeChrBinNbits should be scaled to min(18,log2[max(GenomeLength/NumberOfReferences,ReadLength)])
                # ReadLength is skipped here, as it is unknown
                LpR=$(log2 $((GenomeLength / NumberOfReferences)))
                NBits="--genomeChrBinNbits $(($LpR<18 ? $LpR : 18))"
                printf "NBits: $NBits\n\n" >> {log} 2>&1
            fi

            if [ $GenomeLength -lt 268435456 ]; then
                # for small genomes, --genomeSAindexNbases must be scaled down to min(14, log2(GenomeLength)/2-1)
                logG=$(( $(log2 $GenomeLength) / 2 - 1 ))
                NBases="--genomeSAindexNbases $(( $logG<14 ? $logG : 14 ))"
                printf "NBases: $NBases\n\n" >> {log} 2>&1
            fi

            mkdir -p {output}

            STAR --runMode genomeGenerate --genomeFastaFiles {input.genome} --sjdbGTFfile {input.gtf} \
            --genomeDir {output} --outFileNamePrefix {output}/ \
            --runThreadN {threads} $NBits $NBases {params} >> {log} 2>&1
            """

    rule star_align:
        """
        Align reads against a genome (index) with STAR, and pipe the output to the required sorter(s).
        """
        input:
            reads=get_reads,
            index=expand("{genome_dir}/{{assembly}}/index/{aligner}/", **config)
        output:
            pipe=pipe(expand("{result_dir}/{aligner}/{{assembly}}-{{sample}}.samtools-coordinate.pipe", **config)[0]),
            dir=directory(expand("{result_dir}/{aligner}/{{assembly}}-{{sample}}", **config)),
        log:
            expand("{log_dir}/{aligner}_align/{{assembly}}-{{sample}}.log", **config),
        benchmark:
            expand("{benchmark_dir}/{aligner}_align/{{assembly}}-{{sample}}.benchmark.txt", **config)[0]
        message: explain_rule(f"{config['aligner']}_align")
        params:
            input=lambda wildcards, input: input.reads if sampledict[wildcards.sample]["layout"] == "SINGLE" else input.reads[0:2],
            params=config["align"],
        priority: 0
        threads: 8
        resources:
            mem_gb=30,
        conda:
            "../envs/star.yaml"
        shell:
            """
            trap "find {log} -type f ! -name Log* -exec rm {{}} \;" EXIT
            mkdir -p {log}
            mkdir -p {output.dir}                

            STAR --genomeDir {input.index} --readFilesIn {params.input} --readFilesCommand gunzip -c \
            --outSAMtype BAM Unsorted --outStd BAM_Unsorted \
            --outFileNamePrefix {log}/ --outTmpDir {output.dir}/STARtmp \
            --runThreadN {threads} {params.params} > {output.pipe} 2> {log}/Log.stderr.out

            # move all non-log files to output directory (this way the log files are kept on error)
            find {log} -type f ! -name Log* -exec mv {{}} {output.dir} \;
            """


rule samtools_presort:
    """
    (Pre)sort the result of alignment with the samtools sorter.
    """
    input:
        expand("{result_dir}/{aligner}/{{assembly}}-{{sample}}.samtools-coordinate.pipe", **config),
    output:
        temp(expand("{result_dir}/{aligner}/{{assembly}}-{{sample}}.samtools-coordinate-unsieved.bam", **config)),
    log:
        expand("{log_dir}/samtools_presort/{{assembly}}-{{sample}}.log", **config),
    benchmark:
        expand("{benchmark_dir}/samtools_presort/{{assembly}}-{{sample}}.benchmark.txt", **config)[0]
    params:
        out_dir=f"{config['result_dir']}/{config['aligner']}",
        memory=lambda wildcards, input, output, threads: f"-m {int(1000 * round(config['bam_sort_mem']/threads, 3))}M",
    priority: 0
    threads: 2
    resources:
        mem_gb=config["bam_sort_mem"],
    conda:
        "../envs/samtools.yaml"
    shell:
        """
        # we set this trap to remove temp files when prematurely ending the rule
        trap "rm -f {params.out_dir}/{wildcards.assembly}-{wildcards.sample}.tmp*bam" INT;
        rm -f {params.out_dir}/{wildcards.assembly}-{wildcards.sample}.tmp*bam 2> {log}

        samtools sort -@ {threads} {params.memory} {input} -o {output} \
        -T {params.out_dir}/{wildcards.assembly}-{wildcards.sample}.tmp 2> {log}
        """
