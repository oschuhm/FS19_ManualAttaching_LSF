source(Utils.getFilename("ManualAttaching.lua", g_currentModDirectory))

ManualAttaching_register = {}

function ManualAttaching_register:loadMap()
end

if g_specializationManager:getSpecializationByName("ManualAttaching") == nil then
  if ManualAttaching == nil then 
    print("ERROR: unable to add specialization 'ManualAttaching'")
  else 
    for i, typeDef in pairs(g_vehicleTypeManager.vehicleTypes) do
		if typeDef ~= nil and i ~= "locomotive" and i ~= "trainTrailer" and i ~= "trainTimberTrailer" then 
			local isDrivable  = false
			local isAttachable    = false 
			for name, spec in pairs(typeDef.specializationsByName) do
				if name == "drivable"  then 
					isDrivable = true 
				elseif name == "attachable" then 
					isAttachable = true 
				end 
			end 
			if isDrivable or isAttachable then
			  typeDef.specializationsByName["ManualAttaching"] = ManualAttaching
			  table.insert(typeDef.specializationNames, "ManualAttaching")
			  table.insert(typeDef.specializations, ManualAttaching)  
			end 
		end 
    end   
  end 
end 

print("----ManualAttaching registered.")

addModEventListener(ManualAttaching_register);