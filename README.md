# k6-distributed-cloudrun

A simple Terraform repository to deploy [K6](https://k6.io/) instance with support for containerization, scaling &amp; a grafana dashboard, utilizing cloudrun instances, cloudrun jobs & compute engine instances

Inspired by [XK6 Timescale db demo](https://github.com/grafana/xk6-output-timescaledb) & Walking Tree Technologies' demo on [how to deploy timescale db as compute engine instance](https://walkingtreetech.medium.com/setting-up-a-timescale-db-on-google-compute-engine-163fd9f79e21)

## What is K6 ?
[K6](https://k6.io/) is a tool from grafana for load testing, it has many advantages for using it, including but not limited to

- It uses Javascript which makes it easy to understand & write test cases
- It's open source
- It has multiple [integrations](https://k6.io/docs/integrations/) for different IDEs, different output formats & file parsing as well as a [browser recorder](https://k6.io/docs/test-authoring/create-tests-from-recordings/using-the-browser-recorder/)
- It supports multiple types of tests, like load test, stress test, breakpoint test & [more](https://k6.io/docs/test-types/load-test-types/)
- It supports different protocols
- Allows the user to define their own metrics, thresholds & checks
- Support for community [extensions](https://k6.io/docs/extensions/get-started/explore/)

However like any tool, K6 also has its own shortcomings

- If you need to use 3rd party libraries in Javascript, you will have to [bundle](https://k6.io/docs/using-k6/modules/#bundling-node-modules) them
- The biggest one & the purpose of this article, K6 has minimal support for distributed testing

## Distributed testing
Let's say we have a large stress/load test that we need to execute (tens, maybe hundreds of thousands of users on an app).
You can't simply have that number of users running on a single machine, you need to have multiple machines running in parallel, testing the application at the same time.

K6 does not have native support for that, which means if you have, let's say 3 instances of VMs running tests, then each instance will produce its own report independant of the other instances as K6 is unaware that there are other running instances

Now K6 does have some guides on using [running distributed tests](https://k6.io/blog/running-distributed-tests-on-k8s/) using kuberenets, but that has 2 main shortcomings as well

- You will need a lot of tools & a kuberenets cluster to deploy & run it
- The output of all the pods is still not aggregated, unless you use K6 cloud which is paid. More on it [here](https://k6.io/blog/running-distributed-tests-on-k8s/#metrics-will-not-be-automatically-aggregated-by-default-1)

## How to run a distributed K6 test using cloudrun?

 1. Use a persistent output format from K6. In this case we will be using [xk6 timescaledb](https://k6.io/docs/results-output/real-time/timescaledb/)
 2. . Deploy a cloud rub *job* which runs the K6 script. Cloudrun jobs can run for up to 24 hours & can scale horizontally very easy
 3. Take advantage of K6 tags. By adding tag `testid` to the test, if we have multiple containers running & all of them are saving the data using the same `testid`, then we can aggregate the data from all containers.
 You can add tags to test as follow
 ```
 export const options = {
   tags: {
     testid: __ENV.CLOUD_RUN_EXECUTION,
    }
 }
 ```
 
  4. Deploy a grafana dashboard with a datasource the same as the output of K6 timescaledb to aggregate the results
  5. OPTIONAL. Deploy the timescaledb as a compute engine instance since google cloud sql does not support timescale db
## Technical Implementation
### K6 Docker Image
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
The in the cloudrun job add env variable 
```
K6_OUT=timescaledb=postgresql://<username>:<assword>@$<host>/<db-name>
```
### Grafana Docker Image
Building Grafana's docker image is easier, we just need to copy the datasource configuration & dashboard json into the docker image
here's the Dockerfile
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
### Startup Script for VM instance running a timescaledb server
```
#!/usr/bin/env bash

STARTUP_VERSION=1
STARTUP_MARK=/var/startup.script.$STARTUP_VERSION

# Exit if this script has already ran
if [[ -f $STARTUP_MARK ]]; then
 exit  0
fi

# Install timescale db
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

## How to deploy this terraform code?
- Create `variables.tfvars` file with 
	```
	region =  
	project =  
	# number of parallel tasks for k6
	num-of-tasks =  
	DATABASE_USER =  
	DATABASE_PASSWORD =  
	DATABASE_NAME =  
	# minimum 10 GB
	database-disk-size =  
	```
- Run `terraform apply -var-file=variables.tfvars`

	- This will build & deploy grafana dashboard cloudrun instance, k6 cloudrun jobs, compute engine instance with timescaledb running on it & it will open the firewall in the vpc to allow postgres traffic
	- If you don't want the firewall rule to be deployed, set `add-firewall-rule` to `false` in your variables files
	- ***For MacOS*** user with the apple chip, set `docker-platform` to `linux/amd64`. If you run into error `Error pinging Docker server: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?` then run `sudo ln -s "$HOME/.docker/run/docker.sock" /var/run/docker.sock`

- In your GCP project, go to cloudrun, under `JOBS`, you will see the test job, open the job & run `EXECUTE` which will run the `script.js` file
-  In your GCP project, go to cloudrun, under `SERVICES` you will see the grafana dashboard cloudrun, open its URL & you will see the dashboard up & running.

## Conclusion
There you have it, a fully scalable K6 test instances with dashboards & data aggregation, all deployed from terraform
The dashboard is inspired from [xk6 timescale db config](https://github.com/grafana/xk6-output-timescaledb/blob/main/grafana/dashboards/grafana_dashboard_timescaledb.json) but with modifications to accommodate for parallel tests