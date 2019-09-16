#!/bin/bash
set -e
ELIXIR_VERSION=1.9.1
ERLANG_VERSION=21.3.8.5

export MIX_HOME=$SEMAPHORE_CACHE_DIR/mix
mkdir -p $MIX_HOME

export ERL_HOME="${SEMAPHORE_CACHE_DIR}/.kerl/installs/${ERLANG_VERSION}"

if [ ! -d "${ERL_HOME}" ]; then
    mkdir -p "${ERL_HOME}"
    KERL_BUILD_BACKEND=git kerl build $ERLANG_VERSION $ERLANG_VERSION
    kerl install $ERLANG_VERSION $ERL_HOME
fi

. $ERL_HOME/activate

if ! kiex use $ELIXIR_VERSION; then
    kiex install $ELIXIR_VERSION
    kiex use $ELIXIR_VERSION
fi

mix local.hex --force
mix local.rebar --force
