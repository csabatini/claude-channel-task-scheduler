FROM alpine:latest

# Install python
RUN apk add --no-cache python3 py3-pip git gcc musl-dev python3-dev curl bash
RUN pip3 install --no-cache --upgrade --break-system-packages pip setuptools
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install claude code
RUN apk add ripgrep
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/root/.local/bin:${PATH}"
ENV USE_BUILTIN_RIPGREP=0

RUN mkdir /app
WORKDIR /app

CMD ["tail", "-f", "/dev/null"]