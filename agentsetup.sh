#!/bin/bash

# Parameters
URL=$1
PAT=$2
POOL=$3
AGENT=$4
AGENTTYPE=$5

setup_az_devops() {
    URL=$1
    PAT=$2
    POOL=$3
    AGENT=$4

    echo "About to install components"

    # Install Azure CLI
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

    # Install JDK and Node.js
    sudo apt-get update
    sudo apt-get install -y openjdk-11-jdk nodejs npm

    echo "About to setup Azure DevOps Agent"
    azagentdir="/agent"

    # Test if an old installation exists, if so, delete the folder
    if [ -d "$azagentdir" ]; then
        echo "Cleaning out old directory"
        cd $azagentdir
        servicename=$(cat .service)
        sudo systemctl stop $servicename
        cd /
        sudo rm -rf $azagentdir
    fi

    echo "Creating directory"
    mkdir -p $azagentdir
    cd $azagentdir

    # Get the latest build agent version
    echo "Downloading agent"
    tag=$(curl -s https://api.github.com/repos/Microsoft/azure-pipelines-agent/releases/latest | grep tag_name | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')
    echo "$tag is the latest version"
    download="https://vstsagentpackage.azureedge.net/agent/$tag/vsts-agent-linux-x64-$tag.tar.gz"
    curl -L $download -o agent.tar.gz

    # Expand the tarball
    tar -zxvf agent.tar.gz

    # Run the config script of the build agent
    echo "Configuring Azure DevOps Agent"
    ./config.sh --unattended --url "https://dev.azure.com/$URL" --auth pat --token "$PAT" --pool "$POOL" --agent "$AGENT" --acceptTeeEula --runAsService --replace

    echo "About to start Azure DevOps Agent"
    ./svc.sh install
    ./svc.sh start
}

setup_gh_runner() {
    URL=$1
    PAT=$2
    POOL=$3
    AGENT=$4

    echo "About to setup GitHub Runner"
    ghrunnerdirectory="/actions-runner"

    # Test if an old installation exists, if so, delete the folder
    if [ -d "$ghrunnerdirectory" ]; then
        cd $ghrunnerdirectory
        servicename=$(cat .service)
        sudo systemctl stop $servicename
        cd /
        sudo rm -rf $ghrunnerdirectory
    fi

    # Create a new folder
    mkdir -p $ghrunnerdirectory
    cd $ghrunnerdirectory

    # Get the latest build agent version
    tag=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | grep tag_name | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')
    echo "$tag is the latest version"
    download="https://github.com/actions/runner/releases/download/v$tag/actions-runner-linux-x64-$tag.tar.gz"
    curl -L $download -o ghactionsrunner.tar.gz

    # Expand the tarball
    tar -zxvf ghactionsrunner.tar.gz

    # Run the config script of the build agent
    echo "Configuring GitHub Runner"
    ./config.sh --unattended --url "https://github.com/$URL" --token "$PAT" --runnergroup "$POOL" --replace

    ./svc.sh install
    ./svc.sh start
}

echo "Parameters: URL=$URL, PAT=$PAT, POOL=$POOL, AGENT=$AGENT, AGENTTYPE=$AGENTTYPE"

if [ "${AGENTTYPE,,}" == "azuredevops" ]; then
    setup_az_devops $URL $PAT $POOL $AGENT
else
    setup_gh_runner $URL $PAT $POOL $AGENT
fi