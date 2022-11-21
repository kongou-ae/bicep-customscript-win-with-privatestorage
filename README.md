# bicep-customscript-win-with-privatestorage

This bicep  is for the evaluation of Windows Custom Script extension with the storage account which Private Endpoint is enabled.

This bicep will run the following steps

1. Create a storage account
1. Upload a simple powershell script to this storage account
1. Disable a public internet access on this storage account
1. Create other IaaS environment(VNet, Private Endpoint, Private DNS zone, Virtual Machine etc)
1. Depoloy a custom script extension to a VM 

# Usage

```
New-AzResourceGroup -Name <YOUR-RESOURCE-GROUP> -Location japaneast
New-AzResourceGroupDeployment -Name <YOUR-DEPLOY-GROUP> -ResourceGroupName <YOUR-RESOURCE-GROUP> -TemplateFile .\main.bicep -adminUserName <VM-USERNAME> -adminPassword (ConvertTo-SecureString <VM-PASSWORD> -AsPlainText)
```

After this deployment, you can find customscript.txt in C:\ of customVm01.
