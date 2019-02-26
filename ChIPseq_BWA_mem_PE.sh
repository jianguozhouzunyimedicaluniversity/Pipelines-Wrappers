#!/bin/bash
#####################################
# Usage:	$1=reads1/file/to/path	#
#			$2=reads2/file/to/path	#
#			$3=output_file_prefix	#
#####################################
# check programs: 
which cutadapt &>/dev/null || { echo "cutadapt not found!"; exit 1; }
which bwa &>/dev/null || { echo "bwa not found!"; exit 1; }
which fastqc &>/dev/null || { echo "fastqc not found!"; exit 1; }
which samtools &>/dev/null || { echo "samtools not found!"; exit 1; }
which bedtools &>/dev/null || { echo "bedtools not found!"; exit 1; }
which bedGraphToBigWig &>/dev/null || { echo "bedGraphToBigWig not found!"; exit 1; }

# path to reads
READS1=$1
READS2=$2
NAME=$3
picard=/home/quanyi/app/picard.jar
threads=16

if [ ! -d logs ]
then 
mkdir logs
fi

if [ ! -d fastqc ]
then 
mkdir fastqc
fi 

# fastqc control
fastqc -f fastq -t $threads -o fastqc $1 
fastqc -f fastq -t $threads -o fastqc $2

# cutadapt to trim adaptors
# python3 version required for -j
cutadapt -m 30 -j $threads -a AGATCGGAAGAGC -A AGATCGGAAGAGC -g GCTCTTCCGATCT -G GCTCTTCCGATCT -o $3_R1_trimmed.gz -p $3_R2_trimmed.gz $1 $2 > ./logs/$3_cutadapt.log

# bwa mem alignment
bwa mem -M -t $threads $bwaindex_hg19 $3_R1_trimmed.gz $3_R2_trimmed.gz > $3.sam 

# samtools convert/sort
samtools view -b -@ $threads -o $3.bam $3.sam 
samtools sort -@ $threads -o $3_srt.bam $3.bam

# picard markduplicates
java -jar $picard MarkDuplicates INPUT=$3_srt.bam OUTPUT=$3_mkdup.bam METRICS_FILE=./logs/$3_dup.log REMOVE_DUPLICATES=false

echo 'flagstat after mkdup:' >> ./logs/$3_align.log
samtools flagstat -@ $threads $3_mkdup.bam >> ./logs/$3_align.log

# remove unpaired/unmapped/duplicates/failedQC
# Do NOT do filtering when Pooled ChIPseq!!!
samtools index -@ $threads $3_mkdup.bam
samtools view -@ $threads -f 2 -F 1804 -b -o $3_filtered.bam $3_mkdup.bam
#samtools view -f 2 -F 1536 -b -o $3_filtered.bam $3_mkdup.bam

echo >> ./logs/$3_align.log
echo 'flagstat after filter:' >> ./logs/$3_align.log
samtools flagstat -@ $threads $3_filtered.bam >> ./logs/$3_align.log

# BAM to BW 
#create SE bed from bam
bamToBed -i $3_filtered.bam -split > $3_se.bed

#create plus and minus strand bedgraph
cat $3_se.bed | sort -k1,1 | bedItemOverlapCount hg19 -chromSize=$len_hg19 stdin | sort -k1,1 -k2,2n > $3.bedGraph

bedGraphToBigWig $3.bedGraph $len_hg19 $3.bw

# BAM convert to BED_PE for macs2 peak calling
samtools sort -n -@ $threads -o $3.bam2 $3_filtered.bam
bamToBed -bedpe -i $3.bam2 > $3.bed
cut -f 1,2,6 $3.bed > $3_pe.bed

# clean
rm $3.bam $3.sam $3_R1_trimmed.gz $3_R2_trimmed.gz $3_srt.bam $3.bed $3.bedGraph $3.bam2 $3_se.bed

################ END ################
#          Created by Aone          #
#     quanyi.zhao@stanford.edu      #
################ END ################