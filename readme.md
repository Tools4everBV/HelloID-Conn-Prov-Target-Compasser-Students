# HelloID-Conn-Prov-Target-Compasser-Students

> [!IMPORTANT]
> This connector has been upgraded to a HelloID PowerShell v2 connector and refactored to meet the latest standards.
Please note that it was updated without a working test environment, so we recommend validating it during implementation.

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Compasser-Students](#helloid-conn-prov-target-connectorname)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Compasser-Students_ is a _target_ connector. _Compasser-Students_ provides a set of REST APIs that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks           |
| ----------------------------------------- | --------- | --------------------------------------- | ----------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable       |  No delete available in API |
| **Permissions**                           | ❌         | -                                    |                      |
| **Resources**                             | ❌         | -                                       |                   |
| **Entitlement Import: Accounts**          | ✅⚠️       | -                                       |                   |
| **Entitlement Import: Permissions**       | ❌         | -                                       |                   |
| **Governance Reconciliation Resolutions** | ✅⚠️        | -                                       |                   |


### ⚠️ Entitlement import: Accounts
Inactive accounts might not be returned by the API, according to the API documentation. 

### ⚠️ Governance Reconciliation Resolutions
Governance reconciliation cannot perform delete actions, as there is no delete functionality in the API

## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Compasser-Students/refs/heads/main/Icon.png
```

### Requirements

No special requirements known

### Connection settings

The following settings are required to connect to the API.

|The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| ClientId     | The Oauth Clientid to connect to the API | Yes   |
| ClientSecret | The Oauth ClientSecretto connect to the API | Yes   |
| BaseUrl      | The URL to the API. e.g. https://api.mijnportfolio.nl  | Yes         |
| proxyAddress | The URL to a proxy if required  | No


### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Compasser-Students_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `remote_id`           |

The contents of the remote_id is usually expected to be the studentnumber.  Note that correlation occurs only within the scope of the project_id. The The project_id is automatically determined in the relevant powershell scripts from the contracts in HelloId                 

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `id` property from the portfolio
note that the "account(s)" managed by this connectör are the Portfolio's of the student, not  the  "users" of the system.

## Remarks


create.ps1

- The managed accounts are the "portfolio's" of the student, within the scope of the current active project.
- The project_id is calculated from the location code in the contracts that are in scope.
- The mapping between location and project_id is defined by a table in the script(s)
- Only one project_id can be active at the same time. If the HelloID buisiness rules would result in active accounts on more than one project_id, the script will generate an error message, and no account will be created.
- In the current mapping there is a 1 to 1 relationship between location and project_id. There is an exta check that there is only 1 active location.


Update.ps1.
If the changes would result in a different project_id, it does not update the current account, but archives it, and create/correlates a new account.

- Update of the remote_id value is not allowed. It should never occur, but a check is performed in the script to prevent it.

 Enable.ps1
- Changes the status field of the current account to active

Disable.ps1
- Changes the status field of the current account to inactive (archived)

Import.ps1
- Inactive accounts might not be returned by the API, according to the API documentation. 




## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint     | Description |
| ------------ | ----------- |
|./oauth2/v1/resource/portfolios          | Get the current student accounts (GET)          |
|./oauth2/v1/resource/portfolios          | Create a new student account (POST)|
|./oauth2/v1/resource/portfolios/{id}"   | Get a specific account (on portfolio id)(GET) |
|./oauth2/v1/resource/portfolios/{id}   | Update a specific account (PUT)

### API documentation

<!--
No public documentation available
-->

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
