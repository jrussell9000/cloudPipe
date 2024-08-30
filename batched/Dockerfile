# Copyright 2023 Image Analysis Lab, German Center for Neurodegenerative Diseases(DZNE), Bonn
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# DOCUMENTATION FOR BUILD ARGS (use '--build-arg DEVICE=<VALUE>'):
# - BUILD_BASE_IMAGE:
#   The base image to build the conda and freesurfer build images from
#   - default: ubuntu:22.04
# - RUNTIME_BASE_IMAGE:
#   The base image to build the runtime image on.
#   - default: ubuntu:22.04
# - FREESURFER_BUILD_IMAGE:
#   Image to use to install freesurfer binaries from, the freesurfer binaries
#   should be located in /opt/freesurfer in the image.
#   - default: build_freesurfer
# - CONDA_BUILD_IMAGE:
#   Image to use to install the python environment from, the python environment
#   should be in /venv/ in the image.
#   - default: build_cuda
# - MAMBA_VERSION:
#   Which miniforge file to download to install mamba
#   from https://github.com/conda-forge/miniforge/releases/download/
#   ${FORGE_VERSION}/Miniforge3-${FORGE_VERSION}-Linux-x86_64.sh
#   - default: Miniforge3-23.11.0-0-Linux-x86_64.sh

# DOCUMENTATION FOR TARGETS (use '--target <VALUE>'):
# To select which imaged will be tagged with '-t'
# - runtime:
#   Build the "distributable" image, this is the "final" fastsurfer docker image.
# - build_freesurfer:
#   Build the freesurfer build image only.
# - build_common:
#   Build the basic image with the python enviroment (hardware/driver-agnostic)
# - build_conda:
#   Build the python environment image with cuda/rocm/cpu support

ARG FREESURFER_BUILD_IMAGE=build_freesurfer
ARG CONDA_BUILD_IMAGE=build_conda
ARG RUNTIME_BASE_IMAGE=ubuntu:22.04
ARG BUILD_BASE_IMAGE=ubuntu:22.04
# ARG BUILD_MCR_IMAGE=ubuntu:22.04
# BUILDKIT_SBOM:SCAN_CONTEXT enables buildkit to provide and scan build images
# this is active by default to provide proper SBOM manifests, however, it may also
# include parts that are not part of the distributed image (specifically build image
# parts installed in the build image, but not transfered to the runtime image such as
# git, wget, the miniconda installer, etc.)
ARG BUILDKIT_SBOM_SCAN_CONTEXT=true

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#---------- CREATING BASE IMAGE ----------#
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

#---------- Adding Required Packages & Miniforge ----------#
############################################################

## Start with ubuntu base to build the conda base stage
FROM $BUILD_BASE_IMAGE AS build_base

ENV LANG=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# Install packages needed for build
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      file \
      git \
      upx \
      dnsutils \
      wget && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ARG PYTHON_VERSION=3.10
ARG FORGE_VERSION=23.11.0-0

# Install miniforge
RUN wget --no-check-certificate -qO ~/miniforge.sh \
    https://github.com/conda-forge/miniforge/releases/download/${FORGE_VERSION}/Miniforge3-${FORGE_VERSION}-Linux-x86_64.sh && \
    chmod +x ~/miniforge.sh && \
    ~/miniforge.sh -b -p /opt/miniforge && \
    rm ~/miniforge.sh

ENV PATH /opt/miniforge/bin:$PATH

#---------- Adding Components Common to all Devices----------#
##############################################################

# create a stage for the common components used across different DEVICE settings
FROM build_base AS build_common

# get install scripts into docker
COPY ./env/fastsurfer.yml ./Docker/conda_pack.sh ./Docker/install_env.py ./Docker/abcd/install_abcdtools.py /install/

# Create a base FastSurfer conda environment containing necessary python packages
ARG DEBUG=false
RUN python /install/install_env.py -m base -i /install/fastsurfer.yml \
      -o /install/base-env.yml && \
    mamba env create -f "/install/base-env.yml" | tee /install/env-create.log ; \
    if [ "${DEBUG}" != "true" ]; then \
      rm /install/base-env.yml ; \
    fi

#---------- Setting up the Conda Environment and Installing Python Packages ----------#
#######################################################################################
FROM build_common AS build_conda

ARG DEBUG=true
ARG DEVICE=cu118

# Install packages required by selected device (e.g., tensorflow for cuda)
## First python command adds ABCD requirements, others setup of conda for FastSurfer
RUN python /install/install_env.py -m ${DEVICE} -i /install/fastsurfer.yml \
      -o /install/${DEVICE}-env.yml && \
    mamba env update -n "fastsurfer" -f "/install/${DEVICE}-env.yml" \
      | tee /install/env-update.log && \
    /install/conda_pack.sh "fastsurfer" && \
    echo "DEBUG=$DEBUG\nDEVICE=$DEVICE\n" > /install/build_conda.args ;  \
    if [ "${DEBUG}" != "true" ]; then \
      mamba env remove -n "fastsurfer" && \
      rm -R /install ; \
    fi

#---------- Installing a 'Pruned' Version of FreeSurfer ----------#
###################################################################
# create a stage for pruned Freesurfer
FROM build_base AS build_freesurfer

# get install scripts into docker
COPY ./Docker/install_fs_pruned.sh /install/
SHELL ["/bin/bash", "--login", "-c"]

ARG FREESURFER_URL=default

# install freesurfer and point to new python location
RUN /install/install_fs_pruned.sh /opt --upx --url $FREESURFER_URL && \
rm /opt/freesurfer/bin/fspython &&  \
rm -R /install && \
ln -s /venv/bin/python3 /opt/freesurfer/bin/fspython

# Add freesurfer license file
COPY ./Docker/abcd/fslicense /opt/freesurfer/.license

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#---------- CREATING RUNTIME IMAGE ----------#
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

# =======================================================
# Here, we create references to the requested build image
# =======================================================
# This is needed because COPY --from=<image/stage> does not accept variables as part of The image/stage name
# selected_freesurfer_build_image -> $FREESURFER_BUILD_IMAGE
FROM $FREESURFER_BUILD_IMAGE AS selected_freesurfer_build_image
# selected_conda_build_image -> $CONDA_BUILD_IMAGE
FROM $CONDA_BUILD_IMAGE AS selected_conda_build_image

# =========================================
# Here, we create the smaller runtime image
# =========================================
FROM $RUNTIME_BASE_IMAGE AS runtime

ENV LANG=C.UTF-8

# Add FreeSurfer and python Environment variables
ENV OS=Linux \
    FS_OVERRIDE=0 \
    FIX_VERTEX_AREA="" \
    SUBJECTS_DIR=/opt/freesurfer/subjects \
    FSF_OUTPUT_FORMAT=nii.gz \
    FREESURFER_HOME=/opt/freesurfer \
    PYTHONUNBUFFERED=0 \
    MPLCONFIGDIR=/tmp \
    PATH=/venv/bin:/opt/freesurfer/bin:$PATH \
    MPLCONFIGDIR=/tmp/matplotlib-config

# Install required packages for freesurfer to dry_run
RUN apt-get update && apt-get install -y --no-install-recommends \
      bc \
      curl \
      gawk \
      libgomp1 \
      libquadmath0 \
      liblzma-dev \
      time \
      tcsh \
      unzip \
      wget \
      zlib1g-dev && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    # create matplotlib config dir; make sure we use bash and activate conda env
    # (in case someone starts this interactively)
    mkdir -m 777 $MPLCONFIGDIR && \
    echo "source /venv/bin/activate" >> /etc/bash.bashrc
SHELL ["/bin/bash", "--login", "-c"]

# Copy fastsurfer venv and pruned freesurfer from build images

# Note, since COPY does not support variables in the --from parameter, so we point to a
# reference here, and the
# seletced_<name>_build_image is a only a reference to $<NAME>_BUILD_IMAGE
COPY --from=selected_freesurfer_build_image /opt/freesurfer /opt/freesurfer
COPY --from=selected_conda_build_image /venv /venv

# Copy fastsurfer over from the build context and add PYTHONPATH
COPY . /fastsurfer/
ENV PYTHONPATH=/fastsurfer:/opt/freesurfer/python/packages:$PYTHONPATH \
    FASTSURFER_HOME=/fastsurfer

# Download all remote network checkpoints already, compile all FastSurfer scripts into
# bytecode and update the build file with checkpoints md5sums and pip packages.
RUN cd /fastsurfer ; python3 FastSurferCNN/download_checkpoints.py --all && \
    python3 -m compileall * && \
    python3 FastSurferCNN/version.py --sections +git+checkpoints+pip \
      --build_cache BUILD.info -o fullBUILD.info && \
    mv fullBUILD.info BUILD.info

COPY ./Docker/abcd/ /fastsurfer/abcd/

# Create input, output, and NDATools directories and set their permissions
RUN mkdir /work /log /NDA /.NDATools /.local && \
    chmod 777 /work /log && \
    chmod 777 /fastsurfer/abcd/ABCDfastPipe_Docker_EKS.py && \
    python /fastsurfer/abcd/install_abcdtools.py

# Set up NDA authentication
COPY ./Docker/abcd/keyringrc.cfg /.config/python_keyring/

# TODO: SBOM info of FastSurfer and FreeSurfer are missing, it is unclear how to add
#       those at the moment, as the buildscanner syft does not find simple package.json
#       or pyproject.toml files right now. The easiest option seems to be to "setup"
#       fastsurfer and freesurfer via pip instll.
#ENV BUILDKIT_SCAN_SOURCE_EXTRAS="/fastsurfer"
#ARG BUILDKIT_SCAN_SOURCE_EXTRAS="/fastsurfer"
#RUN <<EOF > /fastsurfer/package.json
#{
#  "name": "fastsurfer",
#  "version": "$(python3 FastSurferCNN/version.py)",
#  "author": "David Kügler <david.kuegler@dzne.de>"
#}
#EOF

# Kubernetes jobs don't let you specify a user to run as, so we need to create it beforehand
ARG USERNAME=nonroot
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

USER $USERNAME

# Set FastSurfer workdir and entrypoint
# the script entrypoint ensures that our conda env is active
WORKDIR "/fastsurfer"
ENTRYPOINT ["/fastsurfer/Docker/entrypoint.sh", "/fastsurfer/abcd/ABCDfastPipe_Docker_EKS.py -b $BATCHINDEX -p"]
FROM demartis/matlab-runtime:2019a AS build_mcr

# # Download the MCR from MathWorks site an install with -mode silent  
# RUN mkdir /mcr-install && \
#     mkdir /opt/mcr && \
#     cd /mcr-install && \
#     wget --no-check-certificate -q https://ssd.mathworks.com/supportfiles/downloads/R2019a/Release/9/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2019a_Update_9_glnxa64.zip && \
#     unzip -q MATLAB_Runtime_R2019a_Update_9_glnxa64.zip && \
#     rm -f MATLAB_Runtime_R2019a_Update_9_glnxa64.zip && \
#     ./install -destinationFolder /opt/mcr -agreeToLicense yes -mode silent && \
#     cd / && \
#     rm -rf mcr-install  

# # Configure environment variables for MCR  
# ENV LD_LIBRARY_PATH /opt/mcr/v96/runtime/glnxa64:/opt/mcr/v96/bin/glnxa64:/opt/mcr/v96/sys/os/glnxa64:/opt/mcr/v96/extern/bin/glnxa64  

# ENV XAPPLRESDIR /etc/X11/app-defaults  

# # Configure a variable to dump VersionInfo.xml and test the correct installation through GitHub Actions
# ENV MCR_MASTER_PATH /opt/mcr/v96

FROM runtime AS runtime_cuda
# to support AWS docker images, see Issue #352
# https://sarus.readthedocs.io/en/stable/user/custom-cuda-images.html#controlling-the-nvidia-container-runtime

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    NVIDIA_REQUIRE_CUDA="cuda>=8.0"
