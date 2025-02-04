# # syntax=docker/dockerfile:1

# # Comments are provided throughout this file to help you get started.
# # If you need more help, visit the Dockerfile reference guide at
# # https://docs.docker.com/go/dockerfile-reference/

# # Want to help us make this template better? Share your feedback here: https://forms.gle/ybq9Krt8jtBL3iCk7

# # Pull base image.
# FROM UBUNTU:22.04

# # Install.
# ARG USERNAME=nonroot
# ARG USER_UID=1000
# ARG USER_GID=$USER_UID

# # Create the user
# RUN groupadd --gid $USER_GID $USERNAME \
#     && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
#     #
#     # [Optional] Add sudo support. Omit if you don't need to install software after connecting.
#     && apt-get update \
#     && apt-get install -y sudo \
#     && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
#     && chmod 0440 /etc/sudoers.d/$USERNAME



# USER $USERNAME

# # Set environment variables.
# ENV HOME /home/nonroot

# # Define working directory.
# WORKDIR /home/nonroot

# # Prevents Python from writing pyc files.
# ENV PYTHONDONTWRITEBYTECODE=1

# # Keeps Python from buffering stdout and stderr to avoid situations where
# # the application crashes without emitting any logs due to buffering.
# ENV PYTHONUNBUFFERED=1

FROM python:3.12-bookworm

# Install.
ARG USERNAME=nonroot
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    #
    # [Optional] Add sudo support. Omit if you don't need to install software after connecting.
    && apt-get update \
    && apt-get install -y sudo git \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

USER $USERNAME
WORKDIR /home/$USERNAME
ENV PATH="/home/$USERNAME/.local/bin:${PATH}"

COPY --chown=$USERNAME:$USERNAME N4BiasFieldCorrection N4BiasFieldCorrection

RUN git clone https://github.com/Washington-University/gradunwarp.git ./gradunwarp && \
    pip install --user -r ./gradunwarp/requirements.txt && \
    pip install ./gradunwarp/. --user && \
    pip install antspyx && \
    chmod +x N4BiasFieldCorrection




# COPY --chown=$USERNAME:$USERNAME requirements.txt requirements.txt
# RUN pip install --user -r requirements.txt



# COPY --chown=worker:worker . .



# CMD ["python"]

# RUN apt install git && \
# git clone https://github.com/Washington-University/gradunwarp.git /home/nonroot/gradunwarp



# RUN python -m pip install -r /home/nonroot/gradunwarp/requirements.txt --root-user-action 

# RUN python -m pip install /home/nonroot/gradunwarp --root-user-action

# # Switch to the non-privileged user to run the application.
# USER nonroot

# # Copy the source code into the container.
# COPY --chown=nonroot:nonroot . /home/nonroot/code

# RUN chown -R nonroot:nonroot /home/nonroot

# # Expose the port that the application listens on.
# EXPOSE 443

# # Run the application.
# ENTRYPOINT ["/home/nonroot/code/entrypoint.sh", "/home/nonroot/code/ndaDownload.py"]
