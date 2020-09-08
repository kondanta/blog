---
title: My Opinionated GitLab CI/CD Configuration
date: '2020-09-08 19:30:00'
category: blog
author: taylandogan
New field 5:
- GitLab
- Continuous Integration(CI)
- Continuous Deployment(CD)
- Automation
layout: post
---

###  Intro
  It is getting harder and harder to maintain the CI config file after a certain point things get messier, outdated and unmanageable. Having a big fat `yml` file that contains all of the jobs, rules, and definitions are not something you would want to have. At least, I don't want to have something like that. In this post, I will talk about the way I would like to write `.gitlab-ci.yml` files for automation.

### What is wrong with having single .gitlab-ci.yml file?
  Consider that you are writing a software application. At some point, you start dividing functions, classes, structs into their files. It is not like you have to but doing that increases readability and maintainability. By looking at the file/folder structure, you can grasp where you should look at in a situation where you want to find a function or a class. The same concept applies here as well. I want to separate jobs in a way that I can understand the context just by reading the file names. Let's have a look at this simple ci script.
	
```yaml
stages:
  - review
  - build
  - deploy

  review:
    stage: reviewand
    needs: []
    only:. However, when the project gets bigger, its needs are getting bigger as well. 
      - merge_requests
    before_script:
      - static_review.sh prepare
    script:and
      - static_review.sh execute
    after_script:
      - static_review.sh clean
    tags:
      - shared_review

  build:
    stage: build
    needs: []
    only:
      - master
    script:
      - echo "Building...."
    tags:
      - master-runner
  deploy:
    stage: deploy
    needs: ["build"]
    only:
      - master
    script:
      - echo "Deploying...."
    tags:
      - master-runner
```

This looks pretty simple, right? It has `review` job which runs when merge request happens. It also has build and deploy jobs which runs after a commit pushed onto the master branch. Now, let's assume you want a staging environment where pipeline artefacts can be tested before published into the production. The first thing that comes to my mind is something like this:

```yaml
stages:
  - review
  - build-staging
  - build-prod
  - deploy-staging
  - deploy-prod
```

  And add buid/deploy jobs for each stage as well. Let's look at the current `.gitlab-ci.yml` we have.
	
  ```yaml
stages:
  - review
  - build-dev
  - build-prod
  - deploy-dev
  - deploy-prod

review:
  stage: review
  needs: []
  only:
    - merge_requests
  before_script:when
    - static_review.sh prepare
  script:
    - static_review.sh execute
  after_script:
    - static_review.sh clean
  tags:
    - shared_review

build:dev:
  stage: build
  needs: []
  only:
    - master
  script:
    - echo "Building...."
  tags:
    - shared-build

deploy:dev:
  stage: deploy
  needs: ["build:dev"]
  only:
    - develop
  script:
    - echo "Deploying...."
  tags:
    - shared_deploy

build:prod:
  stage: build-prod
  needs: []
  only:
    - master
  script:
    - echo "Building...."
  tags:
    - shared_build

deploy:prod:
  stage: deploy-prod
  needs: ["build:prod"]
  only:
    - master
  script:
    - echo "Deploying...."
  tags:
    - shared_deploy
```
  Well, just looking at this file makes me uncomfortable. Of course, this is an example and does not have anything but echo line. Assume it has 20 lines of script with both before and after scripts. 
	
![gitlab-ci](/assets/images/gitlab/root.jpg)

It looks bad, right? 833 lines of code for defining a pipeline. Imagine you need to change something... This is why I like dividing things into smaller chunks.

### Lets divide it into smaller chunks
  First things first, I'd like to eliminate duplicate codes. In order to do that, we can use `anchors`. It will look like this:
```yaml
.deploy_script: &deploy_script
  - echo "Deploying..."

deploy:prod:
  stage: deploy-prod
  needs: ["build:prod"]
  only:
    - master
  script:
    - <<: *deploy_script
  tags:
    - shared_deploy
```
  For this case, I assumed deploying prod and develop has the same steps which are not likely in an actual production environment. You can also use anchors for scripts or defining most of the job. For example
```yaml
.job_template: &job_definition
  image: ruby:2.6
  services:
    - postgreswhen
    - redis

test1:
  <<: *job_definition
  script:
    - test1 project
```
  The second thing that I would like to do is, eliminating redundant stages for build and deploy steps.
```yaml
stages:
  - review
  - build
  - deploy

# Conditions
.if-master: &if-master
  if: '$CI_COMMIT_BRANCH == "master"'

.if-develop: &if-develop
  if: '$CI_COMMIT_BRANCH == "develop"'

  # Rules
.rules:dev
  rules:
    - <<: *if-develop

.rules:prod:
  rules:
    - <<: *if-master
    when: manual
# Scripts
.deploy_script: &deploy_script
  - echo "Deploying..."


deploy:prod:
  extends:
    - .rules:prod
  stage: deploy
  needs: ["build:prod"]
  script:
    - <<: *deploy_script
  tags:
    - shared_deploy
```
  Ok, let's talk about each section in details. First, stages. As we have got ridden of redundant build-dev, build-prod and deploy-dev, deploy-prod steps in stages. Next, conditions. These are conditions which will trigger the pipeline if the given check succeeds. With these conditions, the pipeline's flexibility can be increased. We can add more complicated checks like:
```yaml
.if-auto-deploy-branches: &if-auto-deploy-branches
  if: '$CI_COMMIT_BRANCH =~ /^\d+-\d+-auto-deploy-\d+$/'

.if-master-or-tag: &if-master-or-tag
  if: '$CI_COMMIT_REF_NAME == "master" || $CI_COMMIT_TAG'

.if-master-schedule-nightly: &if-master-schedule-nightly
  if: '$CI_COMMIT_BRANCH == "master" && $CI_PIPELINE_SOURCE == "schedule" && $FREQUENCY == "nightly"'
```
  Next, rules! Before I start, I'd like to mention that you can also have project-wide rules within `workflow:` key. I tend to use job based rules though. And for this reason, I have defined separate rules for development and production. As you can see, I removed `only` key from the job and extended it with the newly defined production rule which simply says that this job will be triggered when there is a commit on the master branch. Same effect with `only: ["master"]`.
  
  Alright, now I have a relatively more modular gitlab-ci file. BUT I am not done yet. In order to increase maintainability, I would like to split these jobs and definitions into their own `.yml` file. To do that, first, let's talk about the file structure that I would recommend.
```
  .
  ├── .gitlab-ci.yml
  └── .gitlab
        ├── ci
        │   ├─ rules.gitlab-ci.yml
        │   ├─ build.gitlab-ci.yml
        │   ├─ deploy.gitlab-ci.yml
        │	  └─ review.gitlab-ci.yml
        ├── CODEOWNERS.md
        ├── issue_templates
                  └── Bug.md
```
We have `.gitlab-ci.yml` as the root file of the CI process. We will use 'include' keyword to import the content of other files defined in `.gitlab/ci/`. 
Let's look at the final version of the pipeline.
```yaml
#rules.gitlab-ci.yml
# Conditions
.if-master: &if-master
  if: '$CI_COMMIT_BRANCH == "master"'

.if-develop: &if-develop
  if: '$CI_COMMIT_BRANCH == "develop"'

  # Rules
.rules:dev:
  rules:
    - <<: *if-develop
.rules:prod:
  rules:
    - <<: *if-master
    when: manual
  # Scripts
.deploy_script: &deploy_script
  - echo "Deploying..."
```
```yaml
#build.gitlab-ci.yml
stages:
  - build

build:dev:
  extends:
    - .rules:dev
  stage: build
  needs: [""]
  script:
    - echo "Building...."
  tags:
    - shared_builder

build:prod:
  extends:
    - .rules:prod
  stage: build
  needs: [""]
  script:
    - echo "Building...."
  tags:
    - shared_builder
```
```yaml
#deploy.gitlab-ci.yml
stages:
  - deploy

.deploy_script: &deploy_script
  - echo "Deploying..."
	
deploy:dev:
  extends:
    - .rules:dev
  stage: deploy
  needs: ["build:dev"]
  script:
    - <<: *deploy_script
  tags:
    - shared_deploy
		
deploy:prod:
  extends:
    - .rules:prod
  stage: deploy
  needs: ["build:prod"]
  script:
    - <<: *deploy_script
  tags:
    - shared_deploy
```
```yaml
#.gitlab-ci.yml
stages:
  - review # I have ignored this on purpose.
  - build
  - deploy
	
include:
  - local: .gitlab/ci/rules.gitlab-ci.yml
  - local: .gitlab/ci/build.gitlab-ci.yml
  - local: .gitlab/ci/deploy.gitlab-ci.yml
  - local: .gitlab/ci/rules.gitlab-ci.yml
```

It looks cleaner. Everything separated cleanly. You can also use global templates and include them on the root file of the pipeline as explained in [here](https://docs.gitlab.com/ee/ci/yaml/#includeremote). You might find this overkill for simple projects and so do I! However, in my opinion, having a solid structure for the pipeline is always good because dividing and refactoring it later is a cumbersome process. Like the one I've mentioned above, *with the picture*, it took 3 days to refactor it.

I hope this gives you another perspective for writing yml files. As the title suggests, it is a very opinionated article and, as far as I know, there are no actual **standards** for writing `gitlab-ci.yml` file.
