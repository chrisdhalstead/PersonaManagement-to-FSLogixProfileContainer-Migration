# PersonaManagement-to-FSLogixProfileContainer-Migration
### Overview

Script to Create FSLogix Profile Container and Migrate VMware Horizon Persona Manager Profiles automatically.

The script will look in the Persona Management share for .V6 profiles which can be migrated, it will then display them into a Grid View item.  You can select multiple Persona Management profiles to migrate.  

Once you have chosen the profiles to migrate, the script will then create a VHD/x in the location you specified with all of the requirements of as FSLogix profile container.  The disk will be attached to the local system with a random drive letter (not in use) and required FSLogix folders and a registry entry will be made.  The profile from persona will then be copied to the FSLogix Profile Container and the disk will be detached from the local system.  The Profile Container is now ready for the user and includes data from the Persona Management profile.

### Usage

This script needs to be run as an Administrator.  Make sure to launch `WindowsPowerShell (Admin)`

![PowerShellAdmin](/Images/PowerShellAdmin.PNG) 



