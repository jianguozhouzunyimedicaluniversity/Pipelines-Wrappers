#!/bin/bash
# set up reads
reads1=$1
reads2=$2
picard=/home/quanyi/app/picard.jar
gatk=/home/quanyi/app/GenomeAnalysisTK/GenomeAnalysisTK.jar
hg19=/home/quanyi/genome/hg19/GRCh37.p13.genome.fa
gatk_bundle_hg19=
bwaindex_hg19=home/quanyi/genome/hg19/BWAindex/
gatk_ref_hg19=
#
cutadapt -f fastq -m 30 -a AGATCGGAAGAGC -A AGATCGGAAGAGC -o R1_trimmed.gz -p R2_trimmed.gz $reads1 $reads2 

# align, sort and mark duplicates: 
bwa mem -M -t 16 -R '@RG\tID:GROUP\tSM:SAMPLE\tPL:illumina\tLB:lib1\tPU:unit1' $bwaindex_hg19 R1_trimmed.gz R2_trimmed.gz > aln.sam 

java -jar $picard SortSam INPUT=aln.sam OUTPUT=sorted_reads.bam SORT_ORDER=coordinate  
java -jar $picard MarkDuplicates INPUT=sorted_reads.bam OUTPUT=dedup_reads.bam METRICS_FILE=metrics.txt
java -jar $picard BuildBamIndex INPUT=dedup_reads.bam
java -jar $picard ReorderSam I=dedup_reads.bam O=ordered_reads.bam R=$hg19 CREATE_INDEX=TRUE

# indel realignment: 
java -jar $gatk -T RealignerTargetCreator -nt 8 -R $gatk_ref_hg19 -I ordered_reads.bam -known $gatk_bundle_hg19/1000G_phase1.indels.hg19.sites.vcf -known $gatk_bundle_hg19/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf -o realignment_targets.list

java -jar $gatk -T IndelRealigner -R $gatk_ref_hg19 -I ordered_reads.bam -targetIntervals realignment_targets.list -known $gatk_bundle_hg19/1000G_phase1.indels.hg19.sites.vcf -known $gatk_bundle_hg19/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf -o realigned_reads.bam 

# Base recalibration: 
java -jar $gatk -T BaseRecalibrator -nct 8 -R $gatk_ref_hg19 -I realigned_reads.bam -knownSites $gatk_bundle_hg19/dbsnp_138.hg19.vcf -knownSites $gatk_bundle_hg19/1000G_phase1.indels.hg19.sites.vcf -knownSites $gatk_bundle_hg19/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf -o recal_data.table
java -jar $gatk -T BaseRecalibrator -R $gatk_ref_hg19 -I realigned_reads.bam -knownSites $gatk_bundle_hg19/dbsnp_138.hg19.vcf -knownSites $gatk_bundle_hg19/1000G_phase1.indels.hg19.sites.vcf -knownSites $gatk_bundle_hg19/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf -BQSR recal_data.table -o post_recal_data.table 
java -jar $gatk -T AnalyzeCovariates  -R $gatk_ref_hg19 -before recal_data.table -after post_recal_data.table -plots recalibration_plots.pdf
java -jar $gatk -T PrintReads -nct 8 -R $gatk_ref_hg19 -I realigned_reads.bam -BQSR recal_data.table -o recal_reads.bam 

# Variant discovery (single sample):
## java -Xmx2g -jar $gatk -T HaplotypeCaller -R $hg19 -I recal_reads.bam --genotyping_mode DISCOVERY -stand_emit_conf 10 -stand_call_conf 30 -o raw_variants.vcf 

# Joint variant discovery (GVCF): 
java -jar $gatk -T HaplotypeCaller -nct 24 -R $gatk_ref_hg19 -I recal_reads.bam --genotyping_mode DISCOVERY --emitRefConfidence GVCF -o raw_variants.g.vcf 

# Genotype (VCF)
java -jar $gatk -T GenotypeGVCFs -D $gatk_bundle_hg19/dbsnp_138.hg19.vcf -R $gatk_ref_hg19 --variant raw_variants.g.vcf -o raw_variants.vcf 

# Hard filter
# SNP filter
java -jar $gatk -T SelectVariants -R $gatk_ref_hg19 -V raw_variants.vcf -selectType SNP -o raw_snps.vcf 
java -jar $gatk -T VariantFiltration -R $gatk_ref_hg19 -V raw_snps.vcf --filterExpression "QD < 2.0 || FS > 60.0 || MQ < 40.0 || MQRankSum < -12.5 || ReadPosRankSum < -8.0" --filterName "snp_filter" -o filtered_snps.vcf 

# INDEL filter
java -jar $gatk -T SelectVariants -R $gatk_ref_hg19 -V raw_variants.vcf -selectType INDEL -o raw_indels.vcf 
java -jar $gatk -T VariantFiltration -R $gatk_ref_hg19 -V raw_indels.vcf --filterExpression "QD < 2.0 || FS > 200.0 || ReadPosRankSum < -20.0" --filterName "indel_filter" -o filtered_indels.vcf

# Merge
java -jar $gatk -T CombineVariants -R $gatk_ref_hg19 --variant filtered_snps.vcf --variant filtered_indels.vcf -o merged_snp_indel_filtered.vcf -genotypeMergeOptions UNIQUIFY

# low genotype quality filter
java -jar $gatk -T VariantFiltration -R $gatk_ref_hg19 -V merged_snp_indel_filtered.vcf -G_filter "GQ < 20.0" -G_filterName lowGQ -o merged_gq_filtered.vcf

# de novo mutations filter
java -jar $gatk -T VariantAnnotator -R $gatk_ref_hg19 -V merged_gq_filtered.vcf -A PossibleDeNovo -o merged_gq_denovo_filtered.vcf

# clean
mv dedup_reads.bam mkdup.bam
rm aln.sam sorted_reads.bam ordered_reads.bam realigned_reads.bam recal_reads.bam