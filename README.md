# HelloID-Conn-SA-Full-Exchange-Online-DistributionGroupManageMemberships

| :warning: Important |
|:---|
| **Best Practice:** Use **HelloID Products** for requesting and managing permissions (group memberships, mailbox access, application roles). Products provide governance, approval workflows, admin visibility, and full lifecycle management.<br>Use delegated forms for one-time operational actions (creating resources like shared mailboxes, password resets, attribute updates) only.<br><br>**[Read more: Products vs. Delegated Forms](https://docs.helloid.com/en/service-automation/products-vs--delegated-forms.html)** |


| :information_source: Information |
|:---|
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

## Description
HelloID-Conn-SA-Full-Exchange-Online-DistributionGroupManageMemberships is a delegated form designed for use with HelloID Service Automation (SA). It can be imported into HelloID and customized according to your requirements.

By using this delegated form, you can manage distribution group memberships in Exchange Online. The following options are available:

1. Search and select a distribution group (wildcard search by display name, description, or mail)
2. View current group members
3. Select users to add to or remove from the distribution group via a dual list
   - The left part of the dual list shows all available users
   - The right part of the dual list shows the users who are currently members of the distribution group
4. Apply membership changes to the distribution group in Exchange Online
   - Users moved to the left part of the dual list will be removed from the group
   - Users moved to the right part of the dual list will be added to the group

## Getting started
### Requirements

#### App Registration & Certificate Setup

Before implementing this connector, make sure to configure a Microsoft Entra ID App Registration. During the setup process, you'll create a new App Registration in the Entra portal, assign the necessary API permissions, and generate and assign a certificate.

Follow the official Microsoft documentation for creating an App Registration and setting up certificate-based authentication:

- [App-only authentication with certificate (Exchange Online)](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps#set-up-app-only-authentication)

#### HelloID-specific configuration

Once you have completed the Microsoft setup and followed their best practices, configure the following HelloID-specific requirements.

- **API Permissions (Application permissions):**
  - `Group.Read.All` - To read distribution group information
  - `GroupMember.Read.All` - To read distribution group memberships
  - `User.Read.All` - To list all users via Graph API for the dual list
  - `Exchange.ManageAsApp` - To manage distribution group memberships
- **Entra ID Role assignment:**
  - Assign the **Exchange Recipient Administrator** (or appropriate Exchange administrative) role to the App Registration
- **Certificate:**
  - Upload the public key file (.cer) in Entra ID
  - Provide the certificate as a Base64 string in HelloID. For instructions on creating the certificate and obtaining the base64 string, refer to our forum post: [Setting up a certificate for Microsoft Graph API in HelloID connectors](https://forum.helloid.com/forum/helloid-provisioning/5338-instruction-setting-up-a-certificate-for-microsoft-graph-api-in-helloid-connectors#post5338)

### Connection settings

The following global variables must be configured in HelloID when importing and configuring the delegated form.

| Setting                        | Description                                               | Mandatory |
| ------------------------------ | --------------------------------------------------------- | --------- |
| EntraIdOrganization            | The Entra organization name (domain)                      | Yes       |
| EntraIdTenantId                | The unique identifier (ID) of your Entra ID tenant        | Yes       |
| EntraIdAppId                   | The unique identifier (ID) of the App Registration in Microsoft Entra ID | Yes |
| EntraIdCertificateBase64String | The Base64-encoded string representation of the app certificate | Yes |
| EntraIdCertificatePassword     | The password associated with the app certificate          | Yes       |

## Remarks

### Performance Optimization Strategy

The connector prioritizes the use of Microsoft Graph API over Exchange Online PowerShell cmdlets wherever possible. The Graph API is significantly faster for data retrieval (Exchange Online cmdlets can take longer to execute, while Graph API typically responds in under a second). However, certain Exchange-specific data and operations are not available via Graph API and still require the Exchange Online module.

### Where Graph API is Used

**Distribution group search:**
- Uses Microsoft Graph API to search for distribution groups
- Filter: `NOT groupTypes/any(c:c eq 'Unified') and mailEnabled eq true and securityEnabled eq false` (mail-enabled security groups that are not Unified/Microsoft 365 groups)
- Supports wildcard search on display name, description, and mail fields
- When `*` is provided as search value, all distribution groups are retrieved
- Why Graph API: Faster retrieval and supports advanced filtering capabilities

**User object retrieval (dual list - left side):**
- All available users are retrieved from Microsoft Graph API
- Properties returned: `id`, `userPrincipalName`, `displayName`, `mail`
- Why Graph API: Fastest method to retrieve user objects

**Group members retrieval (dual list - right side):**
- Current group members are retrieved from Microsoft Graph API using the `/groups/{id}/members` endpoint
- Properties returned: `id`, `displayName`, `userPrincipalName`
- Why Graph API: Faster retrieval and all necessary user properties are returned directly from the members query

### Where Exchange Online Module is Used

**Group membership management:**
- Uses `Add-DistributionGroupMember` cmdlet to add users to distribution groups
- Uses `Remove-DistributionGroupMember` cmdlet to remove users from distribution groups
- Why Exchange Online: These membership management operations are Exchange-specific and not available via Graph API

### Group Filtering

- **Supported Group Types:** The connector filters groups to include distribution groups (mail-enabled security groups). It excludes:
  - Microsoft 365 groups (Unified groups)
  - Security groups (non-mail-enabled)
  - Dynamic distribution groups

### Wildcard Search

- **Search Functionality:** Users can search for distribution groups using a wildcard (`*`) to return all distribution groups, or by entering partial text to search across display name, description, and mail fields. This provides flexible group discovery based on multiple attributes.

### Certificate-Based Authentication

- **JWT Token Generation:** The connector uses certificate-based authentication to generate JSON Web Tokens (JWT) for secure communication with Microsoft Graph API. The certificate is converted from a base64 string and used to sign the JWT assertion for OAuth2 authentication.

### Error Handling

- **Duplicate Member Addition:** If attempting to add a user who is already a member of the distribution group, the operation is skipped with an appropriate audit log entry rather than failing.
- **Member Removal:** If attempting to remove a user who is not a member or if the group no longer exists, the operation is skipped with an informational audit log entry.

## Development resources

### API endpoints

The following Microsoft Graph API endpoints are used by the connector:

| Endpoint | Description |
| -------- | ----------- |
| /v1.0/users | List users |
| /v1.0/groups | List distribution groups |
| /v1.0/groups/{id}/members | List group members |

### PowerShell Cmdlets

The following PowerShell cmdlets are used by the connector:

| Cmdlet | Description |
| ------ | ----------- |
| Connect-ExchangeOnline | Establish session to Exchange Online using certificate-based app-only authentication |
| Add-DistributionGroupMember | Add a user to a distribution group |
| Remove-DistributionGroupMember | Remove a user from a distribution group |
| Disconnect-ExchangeOnline | Close the Exchange Online session |

### Documentation

For more information on the APIs and PowerShell cmdlets used in this connector, please refer to:

**Microsoft Graph API:**
- [Authentication with certificate](https://learn.microsoft.com/graph/auth-v2-service)
- [List users](https://learn.microsoft.com/en-us/graph/api/user-list)
- [List groups](https://learn.microsoft.com/en-us/graph/api/group-list)
- [List group members](https://learn.microsoft.com/en-us/graph/api/group-list-members)

**Exchange Online PowerShell:**
- [Exchange Online PowerShell overview](https://learn.microsoft.com/powershell/exchange/exchange-online-powershell)
- [Connect-ExchangeOnline](https://learn.microsoft.com/powershell/module/exchange/connect-exchangeonline)
- [Add-DistributionGroupMember](https://learn.microsoft.com/powershell/module/exchange/add-distributiongroupmember)
- [Remove-DistributionGroupMember](https://learn.microsoft.com/powershell/module/exchange/remove-distributiongroupmember)
- [Disconnect-ExchangeOnline](https://learn.microsoft.com/powershell/module/exchange/disconnect-exchangeonline)

## Getting help
> :bulb: **Tip:**  
> For more information on Delegated Forms, please refer to our [documentation](https://docs.helloid.com/en/service-automation/delegated-forms.html) pages.

## HelloID docs
The official HelloID documentation can be found at: [https://docs.helloid.com/](https://docs.helloid.com/)
