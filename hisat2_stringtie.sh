#!/bin/bash
#####################################
# Usage:	$1=reads1/file/to/path	#
#			$2=reads2/file/to/path	#
#			$3=output_file_prefix	#
#####################################
# check programs
which cutadapt &>/dev/null || { echo "cutadapt not found!"; exit 1; }
which STAR &>/dev/null || { echo "STAR not found!"; exit 1; }
which hisat2 &>/dev/null || { echo "HISAT2 not found!"; exit 1; }
which fastqc &>/dev/null || { echo "fastqc not found!"; exit 1; }
which stringtie &>/dev/null || { echo "stringtie not found!"; exit 1; }

# path to reads
READS1=$1
READS2=$2
NAME=$3
#gtf=/home/quanyi/genome/hg19/gencode.v19.annotation.gtf
gtf=/home/quanyi/app/PLAR/hg19_ensembl.gtf
index=/home/quanyi/genome/hg19/HISAT2index/genome_tran
STAR_idx=/home/quanyi/genome/hg19/STARindex
threads=8

if [ ! -d logs ];then 
mkdir logs
fi

# fastqc control
fastqc -f fastq -o logs $1 
fastqc -f fastq -o logs $2

# cutadapt--trim adaptors Trueseq index
cutadapt -f fastq -m 20 -a AGATCGGAAGAGC -A AGATCGGAAGAGC -g GCTCTTCCGATCT -G GCTCTTCCGATCT -o $3_R1_trimmed.gz -p $3_R2_trimmed.gz $1 $2 > ./logs/$3_cutadapt.log

# HISAT2--mapping
hisat2 --dta-cufflinks -p $threads -x $index -1 $3_R1_trimmed.gz -2 $3_R2_trimmed.gz -S $3.sam 

samtools view -b -@ $threads $3.sam -o $3.bam
samtools sort -@ $threads $3.bam -o $3_srt.bam

# STAR--mapping
#STAR --genomeDir /home/quanyi/genome/hg19/STARindex --runThreadN $threads --outSAMtype BAM SortedByCoordinate --outFileNamePrefix ./ --readFilesIn $3_R1_trimmed.gz $3_R2_trimmed.gz --readFilesCommand gunzip -c #--outSAMstrandField intronMotif --outFilterIntronMotifs RemoveNoncanonical

#stringtie for transcripts assembly
stringtie -p $threads -G $gtf -l $3 -o $3.gtf $3_srt.bam
#Aligned.sortedByCoord.out.bam #-B

#clean
rm $3_R1_trimmed.gz $3_R2_trimmed.gz $3.bam $3.sam
mv $3_srt.bam $3.bam

################ END ################
#          Created by Aone          #
#     quanyi.zhao@stanford.edu      #
################ END ################