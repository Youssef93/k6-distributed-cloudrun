# k6-distributed-cloudrun

## Introduction

A simple Terraform repository to deploy [k6](https://k6.io/) instance with support for containerization, scaling & a grafana dashboard, utilizing cloudrun instances, cloudrun jobs & compute engine instances

Inspired by [xk6 timescaledb demo](https://github.com/grafana/xk6-output-timescaledb) & Walking Tree Technologies' demo on [how to deploy timescaledb as compute engine instance](https://walkingtreetech.medium.com/setting-up-a-timescale-db-on-google-compute-engine-163fd9f79e21)

## What is k6 ?
[k6](https://k6.io/) is a tool from grafana for load testing, it has many advantages for using it, including but not limited to

- It uses JavaScript which makes it easy to understand & write test cases
- It's open-source
- It has multiple [integrations](https://k6.io/docs/integrations/) for various IDEs & output formats as well as a [browser recorder](https://k6.io/docs/test-authoring/create-tests-from-recordings/using-the-browser-recorder/)
- It supports multiple types of tests, like load test, stress test, breakpoint test & [more](https://k6.io/docs/test-types/load-test-types/)
- It supports different protocols
- Allows users to define their own metrics, thresholds, & checks.
- Supports community [extensions](https://k6.io/docs/extensions/get-started/explore/)

However like any tool, k6 also has its own shortcomings

- If you need to use 3rd party libraries in JavaScript, you will have to [bundle](https://k6.io/docs/using-k6/modules/#bundling-node-modules) them
- The biggest one & the purpose of this article, k6 has minimal support for distributed testing

## Distributed testing
Let's say we have a large stress/load test that we need to execute (tens, maybe hundreds of thousands of users on an app).
You can't simply have that number of users running on a single machine, you need to have multiple machines running in parallel, testing the application at the same time.

k6 does not have native support for that, which means if you have, let's say 3 instances of VMs running tests, then each instance will produce its own report independant of the other instances as k6 is unaware that there are other running instances

Now k6 does have some guides on using [running distributed tests](https://k6.io/blog/running-distributed-tests-on-k8s/) using kuberenets, but that has 2 main shortcomings as well

- You will need a lot of tools & a kuberenets cluster to deploy & run it
- The output of all the pods is still not aggregated, unless you use k6 cloud which is paid. More on it [here](https://k6.io/blog/running-distributed-tests-on-k8s/#metrics-will-not-be-automatically-aggregated-by-default-1)

## How to run a distributed k6 test using cloudrun?

 1. Use a persistent output format from k6. In this case we will be using [xk6 timescaledb](https://k6.io/docs/results-output/real-time/timescaledb/)
 2. . Deploy a cloud run *job* which runs the k6 script. Cloudrun jobs can run for up to 24 hours & can scale horizontally very easy
 3. Take advantage of k6 tags by adding tag `testid` to the test, if we have multiple containers running & all of them are saving the data using the same `testid`, then we can aggregate the data from all containers.
 You can add tags to test as follow
 ```
 export const options = {
   tags: {
     testid: __ENV.CLOUD_RUN_EXECUTION,
    }
 }
 ```
 
  4. Deploy a grafana dashboard with a datasource the same as the output of k6 timescaledb to aggregate the results
  5. OPTIONAL. Deploy the timescaledb as a compute engine instance since google cloud sql does not support timescaledb

## How to deploy this terraform code?
### Requirements & dependencies
- Install the [gcloud cli](https://cloud.google.com/sdk/docs/install) tool
- Install [terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- Login to gcloud cli by running `gcloud auth login`
- Enable these apis on GCP cloud console
	- Artifact Registry
	- Compute Engine
	- Cloud Run
- Install [docker](https://docs.docker.com/engine/install/)
- For **MacOS** users with *Apple* chip
	- Set `docker-platform` to `linux/amd64`. This avoids bugs in docker image built on MacOS machines
	- If you see error `Error pinging Docker server: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?`, then run `sudo ln -s "$HOME/.docker/run/docker.sock" /var/run/docker.sock`
### Deployment steps 
- Create `variables.tfvars` file with 
	```
	region =  
	project =  
	# number of parallel tasks for k6
	num-of-tasks =  
	DATABASE_PASSWORD =  
	DATABASE_NAME =  
	# minimum 10 GB
	database-disk-size =  
	```
- Run `terraform apply -var-file=variables.tfvars`

	- This will build & deploy grafana dashboard cloudrun instance, k6 cloudrun jobs, compute engine instance with timescaledb running on it & it will open the firewall in the vpc to allow postgres traffic
	- If you don't want the firewall rule to be deployed, set `add-firewall-rule` to `false` in your variables files

- In your GCP project, go to cloudrun, under `JOBS`, you will see the test job, open the job & run `EXECUTE` which will run the `script.js` file
-  In your GCP project, go to cloudrun, under `SERVICES` you will see the grafana dashboard cloudrun, open its URL & you will see the dashboard up & running.

## Technical explanation
### k6 docker image
Since we are using cloudrun jobs, we need to build k6 as a docker image with the timescaledb extension
Here's the Dockerfile
```
# Build the k6 binary with the extension
FROM golang:latest
USER root
RUN mkdir /app
WORKDIR /app

RUN go install go.k6.io/xk6/cmd/xk6@latest
COPY . .

# Install extensions
RUN xk6 build \
--with github.com/grafana/xk6-output-timescaledb \
--output /k6
```
In the cloudrun job add env variable 
```
K6_OUT=timescaledb=postgresql://<username>:<assword>@$<host>/<db-name>
```
The docker command (added in cloud run job config) is `["/k6", "run", "script.js"]`
### Grafana docker image
Building grafana's docker image is easier, we just need to copy the datasource configuration & dashboard json into the docker image
Here's the Dockerfile
```
FROM grafana/grafana:latest

COPY ./dashboards /etc/grafana/provisioning/dashboards
COPY ./datasources/datasource.yml /etc/grafana/provisioning/datasources/datasource.yml
```
The datasource.yml should look like this
```
apiVersion: 1

datasources:
  - name: mytimescaledb
    type: postgres
    url: ${DATABASE_HOST}
    database: ${DATABASE_NAME}
    user: ${DATABASE_USER}
    isDefault: true
    secureJsonData:
      password: "${DATABASE_PASSWORD}"
    jsonData:
      sslmode: "require"      # disable/require/verify-ca/verify-full
      maxOpenConns: 0         # Grafana v5.4+
      maxIdleConns: 2         # Grafana v5.4+
      connMaxLifetime: 14400  # Grafana v5.4+
      postgresVersion: 14    # 903=9.3, 904=9.4, 905=9.5, 906=9.6, 1000=10
      timescaledb: true
```
### Startup script for VM instance running a timescaledb server
```
#!/usr/bin/env bash

STARTUP_VERSION=1
STARTUP_MARK=/var/startup.script.$STARTUP_VERSION

# Exit if this script has already ran
if [[ -f $STARTUP_MARK ]]; then
 exit  0
fi

# Install timescaledb
sudo  apt  install  -y  gnupg  postgresql-common  apt-transport-https  lsb-release  wget
sudo  /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh  -y
sudo  echo  "deb https://packagecloud.io/timescale/timescaledb/ubuntu/ $(lsb_release  -c  -s) main" | sudo  tee  /etc/apt/sources.list.d/timescaledb.list
sudo  wget  --quiet  -O  -  https://packagecloud.io/timescale/timescaledb/gpgkey | sudo  apt-key  add  -
sudo  apt  update
sudo  apt  install  -y  timescaledb-2-postgresql-14

# Default configuration
sudo  timescaledb-tune  --quiet  --yes

# Create DB
sudo  -u  postgres  -H  --  psql  -c  "CREATE DATABASE ${DATABASE_NAME};"

# Restart database
sudo  service  postgresql  restart

# Create EXTENSION
sudo  -u  postgres  -H  --  psql  -d  ${DATABASE_NAME}  -c  "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"

# Add listner
sudo  -u  postgres  -H  --  psql  -c  "ALTER SYSTEM SET listen_addresses TO '*';"
sudo  -u  postgres  -H  --  psql  -c  "SELECT pg_reload_conf();"

# Add host of pg
echo  "host all all 0.0.0.0/0 md5" | sudo  tee  -a  /etc/postgresql/14/main/pg_hba.conf >/dev/null

# Reset password
sudo  -u  postgres  -H  --  psql  -c  "ALTER user postgres WITH PASSWORD '${DATABASE_PASSWORD}';"

# Restart PostgreSQL instance
sudo  service  postgresql  restart

touch  $STARTUP_MARK
echo  Done!!!
```

## Security considerations
- The grafana dashboard is public which means anyone can see the data
	-  If you need to protect the data, please remove these environment variables from its cloud run & set it up with the required auth
		- GF_AUTH_ANONYMOUS_ENABLED
		- GF_AUTH_BASIC_ENABLED
		- GF_AUTH_ANONYMOUS_ORG_ROLE
- The grafana cloudrun is public, which means anyone who knows the url can access the dashboard
	- You can remove the resource `"google_cloud_run_service_iam_policy"."noauth-grafana"` in `grafana.tf` file which will make the cloudrun url private. You will need to manage the access from GCP.
- The compute engine instance has an external IP which in production cases might not be suitable
	- You can disable the external ip but the grafana/k6 cloudruns will not able to connect to it.
	- To connect to it using the private ip, deploy a vpc connector & use the private ip as the db host instead of the public ip
- The firewall rule deployed allows all incoming traffic to the postgres port
	- You can allow traffic form certain ip ranges (or tags or service accounts) in the resource `"google_compute_firewall"."allow-postgres-traffic"` in the `vm.tf` file

## Conclusion
There you have it, a fully scalable k6 test instances with dashboards & data aggregation, all deployed from terraform
The dashboard is inspired by [xk6 timescaledb config](https://github.com/grafana/xk6-output-timescaledb/blob/main/grafana/dashboards/grafana_dashboard_timescaledb.json) but with modifications to accommodate for parallel tests