# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-03-02

This is a major version release with a complete refactor to migrate from Azure AD to Entra ID, implement Microsoft Graph API integration, and align with the new HelloID template standards. This version focuses exclusively on **member management** for distribution groups, with owner management functionality removed in favor of a separate dedicated form following HelloID best practices.

### Added

- Microsoft Graph API integration for data retrieval operations
  - New data source for searching distribution groups (`Entra-ID-Get-DistributionGroups-Wildcard-DisplayName-Mail-Description`)
    - Uses Microsoft Graph API to filter distribution groups
    - Filter: `NOT groupTypes/any(c:c eq 'Unified') and mailEnabled eq true and securityEnabled eq false`
    - Excludes Microsoft 365 groups, security groups, and dynamic distribution groups
    - Supports wildcard (`*`) to retrieve all distribution groups
  - New data source for retrieving all users (`EntraID-Get-All-Users`)
    - Uses Microsoft Graph API for fast user retrieval
  - New data source for retrieving distribution group members (`Entra-ID-Get-GroupMembers`)
    - Uses Microsoft Graph API `/groups/{id}/members` endpoint
    - Returns user properties: `id`, `displayName`, `userPrincipalName`
- `Resolve-MicrosoftGraphAPIError` function for comprehensive error handling
- Pagination support with `@odata.nextLink` for complete result sets
- Entra ID-based global variables configuration:
  - `EntraIdOrganization` - The Entra organization name (domain)
  - `EntraIdTenantId` - The unique identifier of your Entra ID tenant
  - `EntraIdAppId` - The unique identifier of the App Registration
  - `EntraIdCertificateBase64String` - Base64-encoded certificate string
  - `EntraIdCertificatePassword` - Certificate password

### Changed

- Enhanced certificate-based authentication with JWT token generation
  - Implements X.509 certificate signing for Microsoft Graph API
  - Uses SHA-256 certificate thumbprint (`x5t#S256`) for enhanced security
- Updated configuration to use Entra ID instead of Azure AD terminology throughout
- Refactored all data sources to align with new HelloID template standards
- Enhanced all-in-one setup script (`createform.ps1`) for better deployment experience
- Improved dynamic form structure and user interface
- Updated task script for better error handling and logging
- Modernized README.md documentation with:
  - Updated App Registration and certificate setup instructions
  - HelloID-specific configuration requirements
  - Connection settings table
  - Performance optimization strategy details
  - Microsoft Graph API endpoints and PowerShell cmdlets reference
  - Group filtering and wildcard search functionality
  - Enhanced certificate-based authentication explanation
  - Comprehensive error handling behavior
- Updated API permissions documentation:
  - `Group.Read.All` - To read distribution group information
  - `GroupMember.Read.All` - To read distribution group memberships
  - `User.Read.All` - To list all users via Graph API
  - `Exchange.ManageAsApp` - To manage distribution group memberships
- Updated Entra ID role assignment requirement: Exchange Recipient Administrator

### Removed

- **Owner management functionality** - In alignment with HelloID best practices, owner management has been removed from this form and should be implemented as a separate delegated form. This separation provides:
  - Better maintainability with focused, single-purpose forms
  - Improved access control by allowing different permissions for member vs. owner management
  - Clearer user experience with dedicated workflows for each management task
- Removed old v1 data source files that were replaced with v2 versions
- Removed deprecated Azure AD-specific configuration
- Cleaned up obsolete script files

## [1.3.0] - 2023-07-17

### Added

- Audit logging functionality for tracking membership changes
- Enhanced logging for better troubleshooting

### Changed

- Replaced global variables with more secure configuration approach
- Refactored variable handling across all data sources
- Updated all-in-one setup script with improved variable configuration

## [1.2.0] - 2022-10-13

### Added

- Certificate-based authentication support for Exchange Online connections
- Support for app-only authentication using certificates
- Enhanced security through certificate authentication
- Updated data sources to support certificate authentication

### Changed

- Updated all data sources to use certificate-based authentication
- Enhanced createform.ps1 to include certificate configuration
- Updated task script to support certificate authentication for Exchange Online
- Improved README.md with certificate setup instructions

## [1.1.0] - 2022-05-09

### Added

- Support for Exchange Online PowerShell v2 module
- Additional data sources for improved functionality
- New data source files for owners, members, and wildcard searches
- Enhanced user table generation data source

### Changed

- Updated all PowerShell scripts to use Exchange Online v2 module cmdlets
- Migrated from Exchange Online v1 to v2 module for better performance
- Updated all-in-one setup script to support v2 module
- Improved task script with v2 module compatibility
- Updated README.md with v2 module requirements

## [1.0.0] - 2022-03-28

This is the initial release of HelloID-Conn-SA-Full-Exchange-Online-DistributionGroupManageMemberships.

### Added

- Initial release of HelloID-Conn-SA-Full-Exchange-Online-DistributionGroupManageMemberships
- Distribution group membership management functionality for Exchange Online
- Form-based distribution group selection with wildcard search across display name, description, and mail fields
- Dual-list interface for managing distribution group memberships
  - Left part shows all available users
  - Right part shows current distribution group members
- Add and remove distribution group membership operations using Exchange Online PowerShell cmdlets
- Task for distribution group membership add/remove operations using Exchange Online cmdlets:
  - `Add-DistributionGroupMember` to add users to distribution groups
  - `Remove-DistributionGroupMember` to remove users from distribution groups
- All-in-one setup script (`createform.ps1`) for HelloID form deployment
- Basic README.md documentation with setup instructions
