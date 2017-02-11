# porterhouse
Framework to orchestrate creation of docker based infrastructures
This tool can replace the docker-compose. In compare to docker-compose porterhouse can execute tasks
(docker provisioning and data population ) as well as tets execution.

## Pre-requisites
Install Ruby, Bundler.

#### Install Porterhouse
``` rake build ```

#### Install Vagrant & plugins
  - Install version 1.65 (Mac and Windows): [vargrant 1.6.5](https://releases.hashicorp.com/vagrant/1.6.5/)
  - **For Linux:**
    - `wget https://releases.hashicorp.com/vagrant/1.6.5/vagrant_1.6.5_x86_64.deb -O /tmp/vagrant_1.6.5_x86_64.deb`
    - `sudo dpkg -i /tmp/vagrant_1.6.5_x86_64.deb`
  - Install [vagrant-triggers](https://github.com/emyl/vagrant-triggers) `vagrant plugin install vagrant-triggers`

  ### Running the Stack - Different Scenarios
  Defining tasks is done in your stack.yaml file. Tasks help you setup all kinds of operations. To **see the tasks** already defined, use:
  ```
  porterhouse --show-tasks
  ```
  To **run chosen tasks**, use:
  ```
  porterhouse --run-tasks=task1,task2

  ```
  You can run tasks together (comma separated) and the order doesn't matter.
  Let's run some initial tasks together: **install s3cmd**, **use local** jars and **start** the stack:
  ```
  porterhouse --run-tasks install-s3cmd, --start --test
  ```

 example of stack.yaml
 ```
registry: docker-hub.io
organization: myorganisation
dockers:
    mysql:
      provisioners:
        - "../../conf.d/scripts/mysql/load_mysql_data.sh"
      volumes:
        - "workdir/mysql-credentials.cnf:/root/.my.cnf"
        - "/btrfs/ssa-qa-mysql-${VAGRANT_NAMESPACE}:/var/lib/mysql"
    memcached:
    selenium-grid:
    elasticsearch:
    appserver-dev:
      provisioners:
        - "../../conf.d/scripts/appserver-dev/ssa_hosts.sh"
        - "../../conf.d/scripts/appserver-dev/disable_xdebug.sh"
      volumes:
        - "../../../:/code_directory

  tasks:
      - "sudo cp workdir/*.inc ../../../../var/config/env/"
      - "sudo chown -R www-data:www-data ../../../../var/"
    snapshot-db:
      - "../../conf.d/scripts/mysql/btrfs-db-snapshot.sh
  tests:
    before:
      - "sudo chown -R www-data:www-data ../../../../var"
    run:
      - "docker exec -t appserver-dev-${VAGRANT_NAMESPACE} ant -buildfile /usr/local/ssa/build.xml \
      -keep-going karma-test"
    after:

 ```
