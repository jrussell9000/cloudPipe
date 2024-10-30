FROM deepmi/fastsurfer:latest

USER root

RUN groupadd --gid 1000 nonroot && \
    useradd --uid 1000 --gid 1000 -m nonroot 

# Switch to the non-privileged user to run the application.
USER nonroot

