
# HelloID-Conn-Prov-Target-Compasser-Students

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="assets/compasserlogo.png">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-Compasser-Students_ is a _target_ connector. Compasser-Students provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint     | Description |
| ------------ | ----------- |
|./oauth2/v1/resource/portfolios          | Get the current student accounts (GET)          |
|./oauth2/v1/resource/portfolios          | Create a new student account (POST)|
|./oauth2/v1/resource/portfolios/$aRef"   | Get a specific account (on portfolio id)(GET) |
|./oauth2/v1/resource/portfolios/$aRef"   | Update a specific account (PUT)

The following lifecycle events are available:

| Event  | Description | Notes |
|---	 |---	|---	|
| create.ps1 | Create (or update) and correlate an Account | - |
| update.ps1 | Update the Account. On location change, archive account on old location and create/activate account on new location | - |
| enable.ps1 | Enable the Account | - |
| disable.ps1 | Disable the Account  |
| delete.ps1 | Delete the account | Not available for this connector |


## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| ClientId     | The Oauth Clientid to connect to the API | Yes   |
| ClientSecret | The Oauth ClientSecretto connect to the API | Yes   |
| BaseUrl      | The URL to the API. e.g. https://api.mijnportfolio.nl  | Yes         |
| proxyAddress | The URL to a proxy if required  | No


### Prerequisites
No specific settings required

### Remarks

General
 - All calls that change values require the project_id as additional input parameter

create.ps1
- When creating an account, the "remote_id" and "project_id" parameters are used for account correlation.
- The "remote_id" contains the StudentNumber (by default the $p.ExternalId of the account)
- The "project_id" is calculated based on the location code in the contracts that are in scope (by default, $_.Location.Code).
- The mapping between location and project_id is defined by a table in the script(s)
- Only one project_id can be active at the same time. If the HelloID buisiness rules would result in active accounts on more than one project_id, the script will generate an error message, and no accounts will be created.
- In the current mapping there is a 1 to 1 relationship between location and project_id. There is an exta check that there is only 1 active location.

Update.ps1.
- Updates the existing account. It compares with the existing account to skip the update if there are no relevant changes.  If the changes would result in a different project_id, it does not update the current account, but archives it, and create/correlates a new account.
- Update of the remote_id value is not allowed. It should never occur, but a check is performed in the script to prevent it.

 Enable.ps1
- Changes the status field of the current account to active

Disable.ps1
- Changes the status field of the current account to inactive (archived)


#### Creation / correlation process

A new functionality is the possibility to update the account in the target system during the correlation process. By default, this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behavior by setting the boolean `$updatePerson` in the `create.ps1` to the value of `$true`.

For this specific connector, a new account will also be created and correlated during the update process, if the location, and therefore the project_id of the person changes, as each student has a separate account (portfolio) for each project_id. By default, if the account on the new project_id already exist, only the status of the account is set to active. To update the other properties, set the boolean `updatePersonOnCreate` in the `update` to the value of `true`.

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The forum topic for discussion about this specific connector can be found at

https://forum.helloid.com/forum/helloid-connectors/provisioning/1293-helloid-conn-prov-target-compasser-students

The official HelloID documentation can be found at: https://docs.helloid.com/
