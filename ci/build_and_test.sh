#!/usr/bin/env bash

# Make sure we fail in case of errors
set -e

# Copy sources (we do not have write permission on the mounted $TRAVIS_BUILD_DIR),
# so let's make a copy of the source code
cd ~
rm -rf my_work_dir
mkdir my_work_dir
# Copy also dot files (.*)
shopt -s dotglob
cp -R ${TRAVIS_BUILD_DIR}/* my_work_dir/

cd my_work_dir

#### borrowed from conda

# Environment
libgfortranver="3.0"

xspec_channel=xspec/channel/dev

if [[ ${TRAVIS_OS_NAME} == linux ]];
then
    miniconda_os=Linux
    compilers="gcc_linux-64 gxx_linux-64 gfortran_linux-64"
else  # osx
    miniconda_os=MacOSX
    compilers="clang_osx-64 clangxx_osx-64 gfortran_osx-64"

    # On macOS we also need the conda libx11 libraries used to build xspec
    # We also need to pin down ncurses, for now only on macos.
    xorg="xorg-libx11 ncurses=5"
fi




# Get the version in the __version__ environment variable
python ci/set_minor_version.py --patch $TRAVIS_BUILD_NUMBER --version_file astromodels/version.py

export PKG_VERSION=$(cd astromodels && python -c "import version;print(version.__version__)")

echo "Building ${PKG_VERSION} ..."

# Update conda
conda update --yes -q conda #conda-build

if [[ ${TRAVIS_OS_NAME} == osx ]];
then
    conda config --add channels conda-forge
fi


conda config --add channels ${xspec_channel}

# Figure out requested dependencies
if [ -n "${MATPLOTLIBVER}" ]; then MATPLOTLIB="matplotlib=${MATPLOTLIBVER}"; fi
if [ -n "${NUMPYVER}" ]; then NUMPY="numpy=${NUMPYVER}"; fi
if [ -n "${XSPECVER}" ];
 then export XSPEC="xspec-modelsonly=${XSPECVER} ${xorg}";
fi

echo "dependencies: ${MATPLOTLIB} ${NUMPY}  ${XSPEC}"

# Answer yes to all questions (non-interactive)
conda config --set always_yes true

# We will upload explicitly at the end, if successful
conda config --set anaconda_upload no

# Create test environment
conda create --name test_env -c conda-forge python=$TRAVIS_PYTHON_VERSION pytest codecov pytest-cov git ${MATPLOTLIB} ${NUMPY} ${XSPEC} ${compilers}\
  libgfortran=${libgfortranver}

# Make sure conda-forge is the first channel
conda config --add channels conda-forge

# Activate test environment
source activate test_env

# Build package

conda build -c conda-forge -c threeml --python=$TRAVIS_PYTHON_VERSION conda-dist/recipe

# Install it
conda install --use-local -c conda-forge -c threeml astromodels xspec-modelsonly-lite

# Run tests
cd astromodels/tests
python -m pytest -vv --cov=astromodels # -k "not slow"

# Codecov needs to run in the main git repo

# Upload coverage measurements if we are on Linux
if [[ "$TRAVIS_OS_NAME" == "linux" ]]; then

    echo "********************************** COVERAGE ******************************"
    codecov -t 493c9a2d-42fc-40d6-8e65-24e681efaa1e

fi

# If we are on the master branch upload to the channel
if [[ "${TRAVIS_EVENT_TYPE}" == "pull_request" ]]; then

        echo "This is a pull request, not uploading to Conda channel"

else

        if [[ "${TRAVIS_EVENT_TYPE}" == "push" ]]; then

            echo "This is a push, uploading to Conda channel"

            conda install -c conda-forge anaconda-client

            echo "Uploading ${CONDA_BUILD_PATH}"
                        
            if [[ "$TRAVIS_OS_NAME" == "linux" ]]; then
                
                anaconda -t $CONDA_UPLOAD_TOKEN upload -u threeml /opt/conda/conda-bld/linux-64/*.tar.bz2 --force
            
            else
            
                anaconda -t $CONDA_UPLOAD_TOKEN upload -u threeml /Users/travis/miniconda/conda-bld/*/*.tar.bz2 --force
            
            fi
        fi
fi
