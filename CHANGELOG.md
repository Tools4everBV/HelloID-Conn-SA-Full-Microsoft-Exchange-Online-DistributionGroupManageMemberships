# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-03-02

This is the initial release of HelloID-Conn-SA-Full-Exchange-Online-DistributionGroupManageMemberships.

### Added

- Initial release of HelloID-Conn-SA-Full-Exchange-Online-DistributionGroupManageMemberships
- Distribution group membership management functionality for Exchange Online
- Form-based distribution group selection with wildcard search across display name, description, and mail fields
- Dual-list interface for managing distribution group memberships
  - Left part shows all available users
  - Right part shows current distribution group members
- Add and remove distribution group membership operations using Exchange Online PowerShell cmdlets
- Certificate-based authentication for both Microsoft Graph API and Exchange Online
  - Implements JWT token generation with X.509 certificate signing
  - Uses SHA-256 certificate thumbprint (`x5t#S256`) for enhanced security
- Data source for searching distribution groups (`Entra-ID-Get-DistributionGroups-Wildcard-DisplayName-Mail-Description`)
  - Uses Microsoft Graph API to filter distribution groups
  - Filter: `NOT groupTypes/any(c:c eq 'Unified') and mailEnabled eq true and securityEnabled eq false`
  - Excludes Microsoft 365 groups, security groups, and dynamic distribution groups
  - Supports wildcard (`*`) to retrieve all distribution groups
- Data source for retrieving all users (`EntraID-Get-All-Users`)
  - Uses Microsoft Graph API for fast user retrieval
- Data source for retrieving distribution group members (`Entra-ID-Get-GroupMembers`)
  - Uses Microsoft Graph API `/groups/{id}/members` endpoint
  - Returns user properties: `id`, `displayName`, `userPrincipalName`
- Task for distribution group membership add/remove operations using Exchange Online cmdlets:
  - `Add-DistributionGroupMember` to add users to distribution groups
  - `Remove-DistributionGroupMember` to remove users from distribution groups
- All-in-one setup script (`createform.ps1`) for HelloID form deployment
- Comprehensive error handling with `Resolve-MicrosoftGraphAPIError` function
- Pagination support with `@odata.nextLink` for complete result sets
- Global variables configuration:
  - `EntraIdOrganization` - The Entra organization name (domain)
  - `EntraIdTenantId` - The unique identifier of your Entra ID tenant
  - `EntraIdAppId` - The unique identifier of the App Registration
  - `EntraIdCertificateBase64String` - Base64-encoded certificate string
  - `EntraIdCertificatePassword` - Certificate password
- Required API permissions:
  - `Group.Read.All` - To read distribution group information
  - `GroupMember.Read.All` - To read distribution group memberships
  - `User.Read.All` - To list all users via Graph API
  - `Exchange.ManageAsApp` - To manage distribution group memberships
- Required Entra ID role assignment: Exchange Recipient Administrator
- Comprehensive README.md documentation including:
  - App Registration and certificate setup instructions
  - HelloID-specific configuration requirements
  - Connection settings table
  - Performance optimization strategy details
  - API endpoints and PowerShell cmdlets reference
  - Group filtering and wildcard search functionality
  - Certificate-based authentication explanation
  - Error handling behavior

### Changed

### Deprecated

### Removed

### Fixed
