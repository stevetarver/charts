## Jenkins upgrades

Our Jenkins upgrade process has the following goals:

* Minimize daily and production build interruptions.
* Don't corrupt the `jenkins_home` directory. This requires a complete Jenkins facility rebuild and longer daily and production build outages.
* Allow all current jobs to be tested in the upgraded environment. This provides confidence that upgrading the main facility will not cause build/deploy outages.
* Provide for rollback to last known-good state. In cases where testing did not reveal all defects, this restores build/deploy quickly.

Concerns:

* Jenkins upgrades are dangerous. They rollout breaking features without identifying them, or even understanding that they broke something.
* Jenkins upgrades cannot be reliably rolled back. The upgrade makes changes to `jenkins_home` that are difficult to unravel, especially piecemeal plugin updates, or plugin updates that have transitive dependencies.
* Jenkins and plugin updates change behavior that may break existing jobs. There are many plugins and wading through all the release notes to identify things that may break existing use is tedious and error prone.

Strategy:

1. Daily jobs are executed on `jenkins.makara.dom`.
2. A separate Jenkins facility is setup on `jenkins-next.makara.dom`
3. Upgrades are applied to `jenkins-next.makara.dom`
4. All jobs from `jenkins.makara.dom` are imported to `jenkins-next.makara.dom` and tested
5. When testing passes:
    * `jenkins.makara.dom` is moved to `jenkins-last.makara.dom`
    * `jenkins-next.makara.dom` is moved to `jenkins.makara.dom`
    * All automatic job execution is paused on `jenkins-last.makara.dom`
1. A new `jenkins-next.makara.dom` is created for the next iteration

Strategy questions:

* Should we copy the PVC hosting `jenkins_home` or start fresh?
    * If we copy, Jenkins will not install our new plugins; it will see existing plugins and bail. If we add new plugins, that could produce unstable transitive plugins. Then we would run an upgrade and that can have shakey results - We wouldn't know if the flaw was in the Jenkins base image or mismatched plugins or the plugin update process. Could lead us down a long path that ends up with some rebuilds and an eventual clean slate deploy.
    * If we start from a clean slate, we can automate job moves, but global configuration, secrets, managed files, plugin setup, etc. would be manual. This would eliminate questions about where faults lie if we have any, and simplify the debug process.
* Should we start from a new node, or deploy to the existing node?
    * A new node is more setup work and since we are deploying from the same OS template, no advances to be had there.
    * A fresh node will eliminate clutter that tends to gather.


## Seeded deploy

Assumes:

* no new node deployed; we are installing the new Jenkins on the existing dev node hosting the previous jenkins deployment.
* 'jenkins-next', 'jenkins', and 'jenkins-last' DNS names exist in domain controllers, and CNAME the k8s cluster ingress.
* 'docker-registry-credentials' are set up in the 'dev' namespace for the target environment

### jenkins-next setup

Set up the new jenkins instance:

1. Log into the cluster node hosting Jenkins.
    * In the k8s dashboard, change to the 'dev' namespace and find the Jenkins pod.
    * Look up the node in the public cloud control portal, searching by IP
    * Log into the node using those credentials 
1. Bash into the Jenkins container
    * `docker ps` to show all containers and locate the container id
    * `docker exec -it {containerId} bash`
1. cd to `/var/jenkins_home`, create a `temp` directory, and `git clone stevetarver/charts` into the temp directory.
1. cd to `/var/jenkins_home/temp/charts/stable/jenkins`
2. Run `helm list` to identify current & next Jenkins releaseId. Jenkins helm releases follow this convention `jenkins-{releaseId}-{location}`. In the case below, we have one jenkins and are setting up the next, so we will choose a releaseId of 1.
    ```
    # helm list | grep "jenkins\|NAMESPACE"
    NAME          REVISION  UPDATED                  STATUS   CHART         NAMESPACE
    jenkins-0-ca3        1  Fri Apr 13 19:22:53 2018 DEPLOYED jenkins-1.0.0 dev
    ```
1. Run `./deploy.sh` in 'jenkins_home' copy mode:
    ```
    ===> Which environment are we in? [p]rod, [d]ev: d
    ===> During the upgrade process, there will be a 'jenkins-next',
         a 'jenkins', and a 'jenkins-last'. Each has a corresponding
         DNS name and we will set the ingress accordingly.
    ===> Which jenkins ingress should be used? [n]ext, [c]urrent, [l]ast: n
    ===> During initial Jenkins setup, we set a large 'initial start delay'
         to allow copying the old jenkins_home to the new one.
    ===> Do you need to copy jenkins_home? [yn]: y
    helm list | grep "jenkins\|NAMESPACE"
    NAME          REVISION  UPDATED                  STATUS   CHART         NAMESPACE
    jenkins-0-dev        1  Fri Apr 13 19:22:53 2018 DEPLOYED jenkins-1.0.0 dev
    ===> The releaseId is the integer between 'jenkins' and {location}
         above. You may pick one of the above, or increment the highest
         number for a fresh deploy.
    ===> Enter the releaseId: 1
    ===> Deploying jenkins-1-dev to dev
         image:   stevetarver/jenkins:2.107.2-r0
         ingress: jenkins-next.makara.dom
         delay:   999999s
    ===> OK to continue? [yn]: y
    ```    
5. Verify the deployment came up properly and the ceph volume is mounted on the dev node
4. On the dev node, copy `/var/jenkins_home` from the current jenkins container to the node (takes several minutes). Logged into the node:
    ```bash
    root:/var/lib/kubelet/plugins/kubernetes.io/rbd/rbd# ll
    total 16
    drwxr-x---  4 root root 4096 Apr 11 18:08 .
    drwxr-x---  3 root root 4096 Aug 25  2017 ..
    drwxr-xr-x  3 root root 4096 Apr 11 21:40 rbd-image-jenkins-0-dev
    drwxr-xr-x 19 1000 root 4096 Apr 11 21:54 rbd-image-jenkins-dev
    root:/var/lib/kubelet/plugins/kubernetes.io/rbd/rbd# cp -r rbd-image-jenkins-dev/* rbd-image-jenkins-0-dev/
    ```
1. Groom the copied jenkins_home for use with the new container:
    1. Delete these directories and files
        * .bash_history
        * .owner
        * ThinBackup Worker Thread.log
        * backups
        * caches
        * copy_reference_file.log
        * fingerprints
        * init.groovy.d
        * installedPlugins.xml
        * logs
        * lost+found
        * nodes
        * plugins
        * temp
        * updates
        * war
        * workflow-libs
        ```bash
        rm -rf .bash_history .owner "ThinBackup Worker Thread.log" backups caches copy_reference_file.log \
            fingerprints init.groovy.d installedPlugins.xml logs nodes plugins temp \
            updates war workflow-libs
        ```
    1. Disable all jobs by running this in the jobs directory
        ```
        find . -iname config.xml -exec sed -ibak 's/<disabled>false<\/disabled>/<disabled>true<\/disabled>/g' {} \;
        ```
    1. Edit `jenkins.model.JenkinsLocationConfiguration.xml`:
        ```
        # change
        <jenkinsUrl>http://jenkins.makara.dom/</jenkinsUrl>
        # to
        <jenkinsUrl>http://jenkins-next.makara.dom/</jenkinsUrl>
        ```
    1. Edit `config.xml`:
        * Delete `securityRealm`
        * Change `<useSecurity>true</useSecurity>` to false
1. Run `./deploy.sh` specifying you don't want to copy 'jenkins_home'
3. Setup 'jenkins-next' GitHub security realm. Copy the security realm xml fragment from PasswordState WOPR/BEIB/jenkins-global password list, 'jenkins-next security realm' to replace the security realm fragment in `jenkins_home/config.xml`

### jenkins-next validation

1. Verify that all configuration and jobs migrated cleanly
2. Build the PoC apps as validation
3. Enable security - follow the initial setup instructions in infra-images
4. Open up to the team to verify their configurations and builds

### jenkins-next migration

With a proven 'next' Jenkins, we are ready to migrate: Change the ingresses so that 'jenkins' becomes 'jenkins-last' and 'jenkins-next' becomes 'jenkins'.

In your Jenkins container:

```
# helm list | grep "jenkins\|NAMESPACE"
NAME          REVISION  UPDATED                  STATUS   CHART         NAMESPACE
jenkins-1-ca3        1  Fri Apr 13 19:22:53 2018 DEPLOYED jenkins-1.0.0 dev
jenkins-0-ca3        1  Fri Apr 13 19:22:53 2018 DEPLOYED jenkins-1.0.0 dev
```

Assuming that `jenkins-1-prod` is 'jenkins-next' and `jenkins-0-prod` is 'jenkins', using the setup from the 'jenkins-next setup' section:

1. Move 'jenkins' to 'jenkins-last': run `./deploy.sh`
    * Which environment: prod
    * Which ingress: jenkins-last
    * Copy jenkins_home: no
    * ReleaseId: 0 - the releaseId for 'jenkins' - this is the target to operate on
1. Update the 'jenkins-last' config
    1. cd to the 'jenkins' jenkins_home via ceph mount or bash into the jenkins container.
    ```
    # For the ceph mount, the directory will be something like:
    ᐅ cd /var/lib/kubelet/plugins/kubernetes.io/rbd/rbd/rbd-image-jenkins-0-ca3/
    ```
    1. Disable all jobs
    ```
    cd jobs
    ᐅ find . -iname config.xml -exec sed -ibak 's/<disabled>false<\/disabled>/<disabled>true<\/disabled>/g' {} \;
    cd ..
    ```
    1. Change the redirect host. Edit `jenkins.model.JenkinsLocationConfiguration.xml`
    ```
    # change
    <jenkinsUrl>http://jenkins.makara.dom/</jenkinsUrl>
    # to
    <jenkinsUrl>http://jenkins-last.makara.dom/</jenkinsUrl>
    ```
    2. Change to use the 'jenkins-last' GitHub security realm. Edit `config.xml` and paste in the 'jenkins-last' GitHub config from Password state.
    3. On the k8s dashboard, delete the pod to force it to pick up the above changes
    4. **TODO** Disable the backup job
1. Move 'jenkins-next' to 'jenkins'
    1. Update the 'jenkins' config
        1. cd to the 'jenkins' jenkins_home
        ```
        ᐅ cd /var/lib/kubelet/plugins/kubernetes.io/rbd/rbd/rbd-image-jenkins-1-ca3/jobs
        ```
        1. Change the redirect host. Edit `jenkins.model.JenkinsLocationConfiguration.xml`
        ```
        # change
        <jenkinsUrl>http://jenkins-next.makara.dom/</jenkinsUrl>
        # to
        <jenkinsUrl>http://jenkins.makara.dom/</jenkinsUrl>
        ```
        2. Change to use the 'jenkins' GitHub security realm. Edit `config.xml` and paste in the 'jenkins' GitHub auth config from Password state and ensure useSecurity is true.
    1. Run `./deploy.sh`
        * Which environment: prod
        * Which ingress: jenkins
        * Copy jenkins_home: no
        * ReleaseId: 1 - the releaseId for 'jenkins-next' - this is the target to operate on
1. In the Jenkins GUI: Jenkins -> Manage Jenkins, click 'Reload Configuration from Disk'
4. Setup GitHub auth:
    1. Jenkins -> Manage Jenkins -> Configure Global Security
    2. Ensure 'Enable security' checked
    3. Security Realm = Github Authentication Plugin selected
    4. Global GitHub OAuth Setting match what was pasted into 'config.xml'
    5. Authorization = Logged-in users can do anything, Allow anonymous read access unchecked
4. **TODO** Enable the backup job
