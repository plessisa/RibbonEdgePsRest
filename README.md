# RibbonEdgePsRest
This project is a Powershell module that allow to control Ribbon SBC Edge with REST API.

It has been started by Vikas Jaswal. http://www.allthingsuc.co.uk/about-me/

Seeing the number of people using this Powershell module and making update on their own, I asked Vikas the authorization to post this code on Github to start a collaboration.
**This project is completely independent from Ribbon Communication. Ribbon is not responsible for any issue with this module. If you have issue with Ribbon product contact the Ribbon support.**

Everyone is free to collaborate on this project or request new feature.

PS: Thanks again Vikas Jaswal for starting this module.

## Key Features

- Built-in cmdlets to query Sonus SBC for transformation tables, transformation entries, systems information, etc.
- Built-in cmdlets to create transformation tables and transformation entries
- Built-in cmdlets to reboot and backup Sonus SBC
- Extensibility – Query, create, modify and delete any UX resource even the one’s which don’t have cmdlets associated!
- Scalability – Manage Sonus SBC’s at scale. Query, create, modify and delete resources with extraordinary efficiency. 1 or 100 SBC’s, it doesn’t matter!
- Simplicity – Extremely simple to use, logical cmdlet naming and in-depth built-in help.

## Pre-requisites

- Sonus SBC software should be R3.0 or higher
- PowerShell v 3.0 or higher
- Ensure you have applied the base version 3.0 license which contains the license for REST
- Ensure you have created a username and password for REST. For more details check out: http://www.allthingsuc.co.uk/accessing-sonus-ux-with-rest-apis/

## Getting Started

1. Download the RibbonEdgePsRest PowerShell module from the button "Clone or downlaod"
2. Copy the module to your machine. Ideally you want to copy the module to one of the following locations as these are default locations where PowerShell looks for modules when import-module is executed.
    - C:\Users\YOURUSERNAME\Documents\WindowsPowerShell\Modules
    - C:\Windows\system32\WindowsPowerShell\v1.0\Modules
3. Open PowerShell and import the module:
    - If the module is in one of the above locations (where PowerShell searches), you can just execute import-module RibbonSBCEdge
    - If the module is not in the default location you can execute import-module C:\RibbonEdgePsRest\RibbonSBCEdge.psm1 (replacing the path where you have copied the module to)
4. To discover what cmdlets are available execute: get-command –module RibbonSBCEdge. Full PowerShell cmdlet help is available for all cmdlets.
5. For complete usage, see: http://www.allthingsuc.co.uk/powershell-module-for-sonus-sbc-10002000/
