# Health Check

Health Check is a script to update progress with swiftDialog including Inventory, Policy Check In, Jamf Protect Check In

This project is heavily inspired from Dan Snelson's project ([Inventory Update Progress](https://snelson.us/2024/02/inventory-update-progress-2/))

Leveraging Bart Reardon's swiftDialog ([swiftDialog](https://github.com/swiftDialog/swiftDialog)) you can show progress windows for things including: Jamf Inventory, Jamf Policy Check In, and Jamf Protect Check In. You can also individually call the commands if you don't want to run all of them together at once. 

Webhooks are enabled to stay informed when someone runs the Health Check and will let you know:

    - Computer name and serial number
    - Computer Model
    - User information ( name and user ID )
    - Operation mode ( what variable was set for the policy )
    - Button to the computer inventory page in Jamf Pro

If you run the complete Health Check and do not have Jamf Protect, it won't run during the script execution. No need to edit the script if you don't want to. 

Health Check examples:


<img width="712" alt="HealthCheck-StartUp" src="https://github.com/AndrewMBarnett/HealthCheck/assets/138056529/3bf173c6-f41a-4955-be3e-684615f0b454">
<img width="712" alt="HealthCheck-SubmitInventory" src="https://github.com/AndrewMBarnett/HealthCheck/assets/138056529/4314ab6f-d6c9-41c1-bcd3-4dcf4d18ec34">
<img width="712" alt="HealthCheck-Complete" src="https://github.com/AndrewMBarnett/HealthCheck/assets/138056529/10f137f4-61b9-4097-abbc-c787ad818821">
<img width="712" alt="HealthCheck-HelpMessage" src="https://github.com/AndrewMBarnett/HealthCheck/assets/138056529/a9fc2e06-32d2-44f7-b43d-51f264e87ebb">
