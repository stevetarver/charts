#!/usr/bin/env bash
#
# Deploy the jenkins helm chart to Kubernetes
#
# There are some advanced configuration options to support Jenkins migration
# that this script helps you choose. See the README.md for more info.
#
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
(
    # Run from helm/charts directory
    cd ${MY_DIR}/..

    MINIKUBE_ENABLED='true'

    # Identify the environment: prod, pre-prod, dev
    echo -n "===> Which environment are we in? [p]rod, [d]ev, [l]ocal: "
    read ANSWER
    if [[ "p" = "${ANSWER}" ]]; then
        #DOMAIN='makara.dom'
        echo "===> '${ANSWER}' is not implemented. Exiting."
        exit 1
    elif [[ "d" = "${ANSWER}" ]]; then
        #DOMAIN='makara.dom'
        echo "===> '${ANSWER}' is not implemented. Exiting."
        exit 1
    elif [[ "l" = "${ANSWER}" ]]; then
        DOMAIN='makara.dom'
        MINIKUBE_ENABLED='true'
    else
        echo "===> '${ANSWER}' is not a valid selection. Exiting."
        exit 1
    fi

    echo "===> During the upgrade process, there will be a 'jenkins-next',"
    echo "     a 'jenkins', and a 'jenkins-last'. Each has a corresponding"
    echo "     DNS name and we will set the ingress accordingly."
    echo -n "===> Which jenkins ingress should be used? [n]ext, [c]urrent, [l]ast: "
    read ANSWER
    if [[ "n" = "${ANSWER}" ]]; then
        INGRESS_HOST='jenkins-next'
    elif [[ "c" = "${ANSWER}" ]]; then
        INGRESS_HOST='jenkins'
    elif [[ "l" = "${ANSWER}" ]]; then
        INGRESS_HOST='jenkins-last'
    else
        echo "===> '${ANSWER}' is not a valid selection. Exiting."
        exit 1
    fi

    # This initial start delay is used to pause jenkins after the ceph cluster
    # is created so we can seed jenkins_home with data from the previous versino
    # It should be very large (999999) on the initial chart deploy, and when
    # file changes are complete, re-install the chart with it set to 0
    echo "===> During initial Jenkins setup, we set a large 'initial start delay'"
    echo "     to allow copying the old jenkins_home to the new one."
    echo -n "===> Do you need to copy jenkins_home? [yn]: "
    read ANSWER
    if [[ "y" = "${ANSWER}" ]]; then
        INITIAL_START_DELAY='999999'
    elif [[ "n" = "${ANSWER}" ]]; then
        INITIAL_START_DELAY='0'
    else
        echo "===> '${ANSWER}' is not a valid selection. Exiting."
        exit 1
    fi

    # The RELEASE_ID allows us to separate jenkins chart deploys and components
    # while deploying to the same cluster and namespace. Release ids are added to
    # all component names.
    # When you are manipulating the current jenkins, you must look up the release id
    # with `helm list`:
    #   NAME          REVISION  UPDATED                  STATUS   CHART         NAMESPACE
    #   jenkins-1     3         Mon Apr  2 16:19:12 2018 DEPLOYED jenkins-1.0.0 dev
    #
    # The release id is the '1' in the NAME 'jenkins-1-lb1'
    # When you are working on the jenkins-next version, you increment the integer
    # RELEASE_ID_NEXT to current + 1.
    helm list | grep "jenkins\|NAMESPACE"
    echo "===> The releaseId is the integer following 'jenkins'"
    echo "     above. You may pick one of the above, or increment the highest"
    echo "     number for a fresh deploy."
    echo -n "===> Enter the releaseId: "
    read ANSWER
    INTEGER_RE='^[0-9]+$'
    if [[ ${ANSWER} =~ ${INTEGER_RE} ]]; then
        RELEASE_ID=${ANSWER}
    else
        echo "===> '${ANSWER}' is not a valid selection. Exiting."
        exit 1
    fi

    IMAGE_NAMETAG='stevetarver/jenkins:2.107.2-r0'
    NAMESPACE='dev'
    RELEASE_NAME="jenkins-${RELEASE_ID}"

    echo "===> Deploying ${RELEASE_NAME} to ${NAMESPACE}"
    echo "     image:    ${IMAGE_NAMETAG}"
    echo "     ingress:  ${INGRESS_HOST}.${DOMAIN}"
    echo "     delay:    ${INITIAL_START_DELAY}s"
    echo "     minikube: ${MINIKUBE_ENABLED}"
    echo -n "===> OK to continue? [yn]: "
    read ANSWER
    if [[ "y" != "${ANSWER}" ]]; then
        echo "===> Exiting at your request"
        exit 1
    fi

    helm upgrade --install --wait                               \
        --namespace=${NAMESPACE}                                \
        --set releaseName=${RELEASE_NAME}                       \
        --set service.initialStartDelay=${INITIAL_START_DELAY}  \
        --set service.image.nameTag=${IMAGE_NAMETAG}            \
        --set ingress.host=${INGRESS_HOST}.${DOMAIN}            \
        --set minikube.enabled=${MINIKUBE_ENABLED}              \
        ${RELEASE_NAME}                                         \
        ./jenkins
)
