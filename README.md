# Creating and Deleting EKS Clusters

The scripts provided in these exercise files will allow you to create and delete Kubernetes
clusters with Elastic Kubernetes Service (EKS) by Amazon Web Services. This README will guide you
on how to do this.

# THIS COSTS MONEY

The resources created by these scripts **will cost you money**.

At this time of writing, an EKS cluster in `us-east-2` costs approx. **$0.10/hour**. This script also
provisions kubelets inside of the cluster, which run on EC2 and are created through the
[Spot market](https://aws.amazon.com/ec2/spot). These instances will cost no more than
**$0.04/hour** total (2 instances * $0.02/hour). 

# How to create clusters

## Setting up your AWS credentials

> **NOTE**: Chapter 0.4 of our course guides you through this process.

1. Create an AWS account. [Go here](https://aws.amazon.com/resources/create-account/)
   to open a new account if you don't already have one.

2. Create an IAM user with no permissions. [Go here](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html)
   to learn how.

   Ensure that the IAM user has "Programmatic-Level Access".

   At the end of the workflow shown above, you should be shown an "Access Key" and a
   "Secret Key." _Save the secret key_ somewhere safe. You will need both of these later,
   but the secret key is irrecoverable once you leave this page.

3. Create an IAM role with an `AdministratorAccess` IAM policy attached to it.
   [Go here](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user.html#roles-creatingrole-user-console)
   to learn how.

   You will be shown an ARN after completing this workflow. _Save this somewhere safe_,
   as you will need it later.

4. Configure the IAM role with a trust policy back to your account and an External ID. The
   External ID will ensure that users can only assume this role if they know what it is.
   [Go here](https://docs.aws.amazon.com/directoryservice/latest/admin-guide/edit_trust.html)
   and [here](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html)
   to learn how.

   You can see your account number by clicking on your name in the upper-right hand corner
   of the AWS console.

## Configuring your shell

1. Install `awscli` by running `brew install awscli` on a Mac or `choco install awscli`
   on a Windows machine.

2. Run `aws configure`. Paste the access and secret keys and your AWS region when prompted.
   You should pick an AWS region that is closest to you. Visit
   [this page](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/)
   to see a list of regions.

   Leave the output format as `json`.

3. Create a temporary secure credentials set with AWS Security Token Service, or STS.
   Use this command to do so:

   ```sh
   $: aws sts assume-role --role-arn [PASTE_ROLE_ARN_HERE] \
    --role-session-name [ANYTHING_YOU_WANT] \
    --external-id [TYPE_EXTERNAL_ID_HERE]
   ```

   This will generate a JSON blob that looks like this:

   ```json
   {
     "Credentials": {
       "AccessKeyId": "ASIA12345...",
       "SecretAccessKey": "abcde12345...",
       "SessionToken": "abcde12345...",
       "Expiration": "123456789"
      }
    }
   ```

4. Copy the text next to `AccessKeyId`, then run: `export AWS_ACCESS_KEY_ID=[PASTE_HERE]`.
   (Replace `[PASTE_HERE]` with what you just copied.)
5. Copy the text next to `SecretAccessKey`, then run: `export AWS_SECRET_ACCESS_KEY=[PASTE_HERE]`.
   (Replace `[PASTE_HERE]` with what you just copied.)
6. Copy the text next to `SessionToken`, then run: `export AWS_SESSION_TOKEN=[PASTE_HERE]`.
   (Replace `[PASTE_HERE]` with what you just copied.)
7. Verify that you are now an admin by running: `aws iam list-roles`. You should get a JSON
   object back.

## Creating your cluster

1. Create an S3 bucket to store information about the cluster that you'll be creating:
   `aws s3 mb s3://[RANDOM_STRING]_kubernetes_fundamentals`.

   (Replace `[RANDOM_STRING]` with anything you want.)

2. Run the `create_cluster` script like this:

   ```
   TERRAFORM_S3_BUCKET=[BUCKET_FROM_STEP_1] TERRAFORM_S3_KEY=state create_cluster.sh
   ```

   This will take approximately 20 minutes to complete.

## Verifying that your cluster works

Once you've created your cluster, verify that it works by following these steps:

1. Create or update your Kubeconfig:
   `aws eks update-kubeconfig --cluster-name explore-california-cluster`

2. Ensure that your nodes show up:
   `kubectl get nodes`

## Deleting your cluster

Run this to delete your cluster:

```
TERRAFORM_S3_BUCKET=[BUCKET_FROM_STEP_1] TERRAFORM_S3_KEY=state delete_cluster.sh
```
