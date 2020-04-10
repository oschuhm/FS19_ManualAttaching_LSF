--
-- FS19 - ManualAttaching
-- With this mod you need to get out of the vehicle to attach or detach implement / trailer.
--	-drive vehicle to implement, get out and move to attacherjoint
--	-you will see attaching markers
--	-you also need to manually attach PTO.
--	-you need to detach PTO first before detach implement
--	-you can switch between 3 mods of attaching (Manually only, Inside vehicle only and Both Manually / Insid)
--	-if PTO is not connected, implement cant be turned on / start tipping
--	-you can show / hide current MA mode in F1 help menu
--
--Controls:
--	Attach / detach implement - "KEY_q"
--	Attach / detach PTO - "KEY_x"
--	Toglle mode - "KEY_lshift KEY_a"
--	Show / hide mode in help menu - "KEY_lctrl KEY_a"
--
-- @author:    	kenny456 (kenny456@seznam.cz) / Burner
-- @history:	v1.0 - 2019-02-08 - first version
--				V1.1 - 2019-02-12 - fixed these errors:
--									-line 58: when you start new game as farm manager or start from scratch
--									-line 438: when detaching PTO from trailer with PTO function
--									-line 250: when start tipping with trailer with PTO function and no PTO attached
--									-line 271: when attaching two conveyor belt (or any with driveable spec)
--									-line 271: when attaching two conveyor belt (or any with driveable spec)
--									-line 491: when detaching implement from attacherVehicle with no MA spec.
--
ManualAttaching = {};
local ManualAttaching_directory = g_currentModDirectory;

if g_dedicatedServerInfo == nil then
  local file, id
  ManualAttaching.sounds = {}
  for _, id in ipairs({"attach_pto"}) do
    ManualAttaching.sounds[id] = createSample(id)
    file = ManualAttaching_directory.."Sounds/"..id..".ogg"
    loadSample(ManualAttaching.sounds[id], file, false)
  end
end

function ManualAttaching.prerequisitesPresent(specializations)
	return true
end

function ManualAttaching.initSpecialization()
end

function ManualAttaching.registerOverwrittenFunctions(vehicleType)
	if ManualAttaching.MAPlayer == nil then
		Player.registerActionEvents = Utils.appendedFunction(Player.registerActionEvents, ManualAttaching.registerActionEventsPlayer);
		Player.update = Utils.appendedFunction(Player.update, ManualAttaching.updatePlayer);
		ManualAttaching.MAPlayer = true
	end
end

function ManualAttaching.registerFunctions(vehicleType)
end

function ManualAttaching.registerEvents(vehicleType)
end

function ManualAttaching:registerActionEventsPlayer()
	for _,actionName in pairs({ "MA_ATTACH", "MA_PTO_ATTACH", "MA_TOGGLE_MODE_PLAYER" } ) do
		local __, eventName = InputBinding.registerActionEvent(g_inputBinding, actionName, self, ManualAttaching.actionCallbackPlayer ,true ,true ,false ,true)
		if ManualAttaching.MAEP == nil then
			ManualAttaching.MAEP = {}
		end
		ManualAttaching.MAEP[actionName] = eventName
		if g_inputBinding ~= nil and g_inputBinding.events ~= nil and g_inputBinding.events[eventName] ~= nil then
			g_inputBinding.events[eventName].displayIsVisible = false
		end
	end
end

function ManualAttaching:registerActionEventsMenu()
end

function ManualAttaching:onRegisterActionEvents(isSelected, isOnActiveVehicle)
	if not self.isClient then
		return
	end
	if SpecializationUtil.hasSpecialization(Drivable, self.specializations) then
		if isOnActiveVehicle and self:getIsControlled() then
			if self.MAE == nil then 
				self.MAE = {}
			else	
				self:clearActionEventsTable( self.MAE )
			end 
			for _,actionName in pairs({ "MA_TOGGLE_MODE", "MA_TOGGLE_HELP_MENU" } ) do
				local _, eventName = self:addActionEvent(self.MAE, InputAction[actionName], self, ManualAttaching.actionCallback, true, true, false, true, nil);
				if g_inputBinding ~= nil and g_inputBinding.events ~= nil and g_inputBinding.events[eventName] ~= nil then
					if isSelected then
						g_inputBinding.events[eventName].displayPriority = 1
					elseif  isOnActiveVehicle then
						g_inputBinding.events[eventName].displayPriority = 1
					end
					g_inputBinding.events[eventName].displayIsVisible = ManualAttaching.showHelp
					if actionName == 'MA_TOGGLE_HELP_MENU' then
						g_inputBinding.events[eventName].displayIsVisible = false
					end
				end
			end
		end
	end
end

function ManualAttaching.registerEventListeners(vehicleType)
	for _,n in pairs( { "onLoad", "onPostLoad", "saveToXMLFile", "onUpdate", "onUpdateTick", "onDraw", "onReadStream", "onWriteStream", "onRegisterActionEvents", "registerActionEventsPlayer", "onAttach", "onDetach" } ) do
		SpecializationUtil.registerEventListener(vehicleType, n, ManualAttaching)
	end
end

function ManualAttaching:onLoad(vehicle)
	self.ma = {}
	self.ma.mode = 1
	ManualAttaching.inputAttach = false
	ManualAttaching.inputPtoAttach = false
	ManualAttaching.inputToggleModePlayer = false
	ManualAttaching.showHelp = true
	self.togglePTO = ManualAttaching.togglePTO
	self.playManualAttachSound = ManualAttaching.playManualAttachSound
	self.playManualAttachPTOSound = ManualAttaching.playManualAttachPTOSound
	self.toggleMaMode = ManualAttaching.toggleMaMode
	self.getDriveableAttacherVehicle = ManualAttaching.getDriveableAttacherVehicle
	if ManualAttaching.MAEP == nil then
		ManualAttaching.MAEP = {}
	end
	self.avBackup = nil;
	self.avJointDescIndex = nil;
	self.isDetachAllowed = Utils.overwrittenFunction(self.isDetachAllowed, ManualAttaching.isDetachAllowed)
	self.getCanBeTurnedOn = Utils.overwrittenFunction(self.getCanBeTurnedOn, ManualAttaching.getCanBeTurnedOn)
	self.getCanToggleAttach = Utils.overwrittenFunction(self.getCanToggleAttach, ManualAttaching.getCanToggleAttach)
	self.postAttach = Utils.appendedFunction(self.postAttach, ManualAttaching.postAttach)
	self.preDetach = Utils.appendedFunction(self.preDetach, ManualAttaching.preDetach)
	self.ma.hasPto = false
end

function ManualAttaching:onPostLoad(savegame)
	if self.spec_attacherJoints.attacherJoints ~= nil then
		for k,jointDesc in pairs(self.spec_attacherJoints.attacherJoints) do
			jointDesc.ptoAttached = true;
			if self.spec_powerTakeOffs ~= nil then
				local ptoOutput = {}
				if #self.spec_powerTakeOffs.outputPowerTakeOffs > 0 then
					ptoOutput = self:getOutputPowerTakeOffsByJointDescIndex(k)
					jointDesc.ptoOutput = ptoOutput
				end
			end
		end;
	end;
	if savegame ~= nil then
		local xmlFile = savegame.xmlFile
		local key     = savegame.key ..".ManualAttaching"
		if self.spec_attacherJoints ~= nil then
			for k, jointDesc in pairs(self.spec_attacherJoints.attacherJoints) do
				if jointDesc.ptoOutput ~= nil then
					local keyString = string.format("#attacherJoint%dptoAttached", k);
					local state = Utils.getNoNil(getXMLBool(xmlFile, key .. keyString), true);
					if state == false then
						self:togglePTO(k, state, true);
					end;
				end;
			end;
		end;
		self.ma.mode = Utils.getNoNil(getXMLInt(xmlFile, key.."#MaMode"), self.ma.mode);
		ManualAttaching.showHelp = Utils.getNoNil(getXMLBool(xmlFile, key.."#MaShowHelp"), ManualAttaching.showHelp);
	end
end
function ManualAttaching:saveToXMLFile(xmlFile, key)
	local numToSave = 0;
	local attributes = nil;
	if self.spec_attacherJoints ~= nil then
		if self.spec_attacherJoints.attacherJoints ~= nil then
			for k, jointDesc in pairs(self.spec_attacherJoints.attacherJoints) do
				if jointDesc.ptoOutput ~= nil then
					numToSave = numToSave + 1;
				end;
			end;
		end;
	end;
	if self.spec_attacherJoints ~= nil then
		for k, jointDesc in pairs(self.spec_attacherJoints.attacherJoints) do
			if jointDesc.ptoOutput ~= nil then
				if jointDesc.ptoAttached == false then
					setXMLBool(xmlFile, key.."#attacherJoint" .. k .. "ptoAttached",    	jointDesc.ptoAttached)
				end;
			end;
		end;
	end;
	setXMLInt(xmlFile, key.."#MaMode",    	self.ma.mode)
	setXMLBool(xmlFile, key.."#MaShowHelp",    	ManualAttaching.showHelp)
end
function ManualAttaching:onUpdate(dt)
	if self:getIsActive() then
		if SpecializationUtil.hasSpecialization(Drivable, self.specializations) then
			if self.spec_attacherJoints ~= nil then
				for _, implement in pairs(self.spec_attacherJoints.attachedImplements) do
					local object = implement.object;
					if object ~= nil then
						local jointDescIndex = implement.jointDescIndex;
						local jointDesc = self.spec_attacherJoints.attacherJoints[jointDescIndex];
						local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex;
						local attacherJoint = object.spec_attachable.inputAttacherJoints[inputJointDescIndex];
						if jointDesc.ptoOutput ~= nil and jointDesc.ptoAttached == false then
							local vehicle = self;
							local tipVehicle = nil;
							local dischargeVehicle = self;
							if self.spec_turnOnVehicle ~= nil then
								if self.spec_turnOnVehicle.isTurnedOn == nil then
									vehicle = object;
								end;
							else
								vehicle = object;
							end;
							if object.spec_trailer ~= nil then
								if object.spec_trailer.tipState ~= nil then
									tipVehicle = object;
								end;
							end;
							if self.spec_dischargeable ~= nil then
								if self.spec_dischargeable.currentDischargeState == 0 then
									dischargeVehicle = object;
								end;
							else
								dischargeVehicle = object;
							end;
							for _, childImplement in pairs(object.spec_attacherJoints.attachedImplements) do
								local childObject = childImplement.object;
								if childObject ~= nil then
									if childObject.spec_turnOnVehicle ~= nil then
										if childObject.spec_turnOnVehicle.isTurnedOn ~= nil then
											vehicle = childObject;
										end;
									end;
									if childObject.spec_trailer ~= nil then
										if childObject.spec_trailer.tipState ~= nil then
											tipVehicle = childObject;
										end;
									end;
								end;
							end;
							if vehicle.spec_turnOnVehicle ~= nil then
								if vehicle.spec_turnOnVehicle.isTurnedOn then
									if self.isAIThreshing ~= nil then
										if self.isAIThreshing then
											self:stopAIThreshing();
										end;
									end;
									if self.isAITractorActivated ~= nil then
										if self.isAITractorActivated then
											self:stopAITractor();
										end;
									end;
									vehicle:setIsTurnedOn(false);
									g_currentMission:showBlinkingWarning(g_i18n:getText("MA_PTO_ATTACH_WARNING"), 2000);
								end;
							end;
							if tipVehicle ~= nil then
								if tipVehicle.spec_trailer ~= nil then
									if tipVehicle.spec_trailer.tipState == Trailer.TIPSTATE_OPENING or tipVehicle.spec_trailer.tipState == Trailer.TIPSTATE_OPEN then
										tipVehicle:stopTipping();
										g_currentMission:showBlinkingWarning(g_i18n:getText("MA_PTO_ATTACH_WARNING"), 2000);
									end;
								end;
							end;
							if dischargeVehicle ~= nil then
								if dischargeVehicle.spec_dischargeable ~= nil then
									if dischargeVehicle.spec_dischargeable.currentDischargeState == 1 or dischargeVehicle.spec_dischargeable.currentDischargeState == 2 then
										dischargeVehicle:setDischargeState(0);
										g_currentMission:showBlinkingWarning(g_i18n:getText("MA_PTO_ATTACH_WARNING_UNLOAD"), 2000);
									end;
								end;
							end;
						end;
					end;

				end;
			end;
			if self.MAE ~= nil then
				if self.ma.mode == 1 then
					g_inputBinding:setActionEventText(self.MAE.MA_TOGGLE_MODE.actionEventId, g_i18n:getText("MA_MODE_1"))
				elseif self.ma.mode == 2 then
					g_inputBinding:setActionEventText(self.MAE.MA_TOGGLE_MODE.actionEventId, g_i18n:getText("MA_MODE_2"))
				elseif self.ma.mode == 3 then
					g_inputBinding:setActionEventText(self.MAE.MA_TOGGLE_MODE.actionEventId, g_i18n:getText("MA_MODE_3"))
				end
			end
		end;
	end;
end
function ManualAttaching:onUpdateTick(dt)
end
function ManualAttaching:updatePlayer(dt)
	if g_currentMission.player ~= nil then
		if g_currentMission.player.attacherSearchNode == nil then
			g_currentMission.player.attacherSearchNode = createTransformGroup("attacherSearchNode");
			link(g_currentMission.player.lightNode, g_currentMission.player.attacherSearchNode);
			setTranslation(g_currentMission.player.attacherSearchNode, 0, 0, -2);
		end;
	end;
	g_inputBinding:setActionEventTextVisibility(ManualAttaching.MAEP['MA_TOGGLE_MODE_PLAYER'], false)
	g_inputBinding:setActionEventTextVisibility(ManualAttaching.MAEP['MA_ATTACH'], false)
	g_inputBinding:setActionEventTextVisibility(ManualAttaching.MAEP['MA_PTO_ATTACH'], false)
	for k,v in pairs(g_currentMission.vehicles) do
		if v.ma ~= nil then
			local nearestFarmerDistance = 1.1;
			local nearestAttachersDistance = 2;
			local foundImplement = nil;
			if v.spec_attacherJoints ~= nil then
				for attacherJointIndex, jointDesc in pairs(v.spec_attacherJoints.attacherJoints) do
					local xNew = jointDesc.jointOrigTrans[1];
					local yNew = jointDesc.jointOrigTrans[2];
					local zNew = jointDesc.jointOrigTrans[3];
					local px, py, pz = localToWorld(getParent(jointDesc.jointTransform), xNew, yNew, zNew);
					for _, attachable in pairs(g_currentMission.attachables) do
						for inputAttacherIndex, attacherJoint in pairs(attachable.spec_attachable.inputAttacherJoints) do
							local ptoOutput = {}
							local ptoInput = {}
							if v.spec_powerTakeOffs ~= nil then
								if #v.spec_powerTakeOffs.outputPowerTakeOffs > 0 then
									ptoOutput = v:getOutputPowerTakeOffsByJointDescIndex(attacherJointIndex)
									jointDesc.ptoOutput = ptoOutput
								end
							end
							if attachable.spec_powerTakeOffs ~= nil then
								if #attachable.spec_powerTakeOffs.inputPowerTakeOffs > 0 then
									ptoInput = attachable:getInputPowerTakeOffs(inputAttacherIndex)
									attacherJoint.ptoInput = ptoInput
								end
							end
							if attachable.spec_attachable.attacherVehicle == nil and attacherJoint.jointType == jointDesc.jointType then
								local vx, vy, vz = getWorldTranslation(attacherJoint.node);
								local distance = MathUtil.vector3Length(px-vx, py-vy, pz-vz);
								if distance < nearestAttachersDistance then
									foundImplement = attachable;
									if g_currentMission.player ~= nil then
										local pvx, pvy, pvz = getWorldTranslation(g_currentMission.player.attacherSearchNode);
										local farmerDistance = MathUtil.vector3Length(pvx-px, pvy-py, pvz-pz);
										if farmerDistance < nearestFarmerDistance and foundImplement ~= nil then								
											local vehicle = nil
											local driveableVehicle = v:getDriveableAttacherVehicle(v)
											if driveableVehicle ~= nil then
												vehicle = driveableVehicle
											else
												vehicle = v
											end
											if driveableVehicle ~= nil then
												if ManualAttaching.inputToggleModePlayer == true then
													ManualAttaching.inputToggleModePlayer = false
													vehicle:toggleMaMode()
												end
												g_inputBinding:setActionEventTextVisibility(ManualAttaching.MAEP['MA_TOGGLE_MODE_PLAYER'], true)
												g_inputBinding:setActionEventText(ManualAttaching.MAEP['MA_TOGGLE_MODE_PLAYER'], g_i18n:getText("MA_MODE_"..vehicle.ma.mode))
												if vehicle.ma.mode == 1 or vehicle.ma.mode == 3 then
													g_inputBinding:setActionEventTextVisibility(ManualAttaching.MAEP['MA_ATTACH'], true)
													g_inputBinding:setActionEventText(ManualAttaching.MAEP['MA_ATTACH'], g_i18n:getText("MA_ATTACH"))
													local sx, sy, sz = project(px, py, pz);
													local sx1, sy1, sz1 = project(vx, vy, vz);
													setTextAlignment(RenderText.ALIGN_CENTER);
													setTextBold(false);		
													setTextColor(0.235, 0.6, 0.137, 1.0);
													for i=1, 10 do
														renderText(sx, sy, 0.1, ".");
														renderText(sx1, sy1, 0.1, ".");
													end;									
													if ManualAttaching.inputAttach then
														ManualAttaching.inputAttach = false
														v:attachImplement(attachable, inputAttacherIndex, attacherJointIndex);
														if jointDesc.ptoOutput ~= nil and attacherJoint.ptoInput ~= nil then
															v:togglePTO(attacherJointIndex, false);
														end;
													end;
												end;
											end;
										end
									end;
								end;
							elseif attachable.spec_attachable.attacherVehicle == v and attacherJoint.jointType == jointDesc.jointType then
								local vx, vy, vz = getWorldTranslation(attacherJoint.node);
								local distance = MathUtil.vector3Length(px-vx, py-vy, pz-vz);
								if distance < nearestAttachersDistance then
									foundImplement = attachable;
									if g_currentMission.player ~= nil then
										local pvx, pvy, pvz = getWorldTranslation(g_currentMission.player.attacherSearchNode);
										local farmerDistance = MathUtil.vector3Length(pvx-px, pvy-py, pvz-pz);
										if farmerDistance < nearestFarmerDistance and foundImplement ~= nil then
											local vehicle = nil
											local driveableVehicle = v:getDriveableAttacherVehicle(v)
											if driveableVehicle ~= nil then
												vehicle = driveableVehicle
											else
												vehicle = v
											end
											if driveableVehicle ~= nil then
												if ManualAttaching.inputToggleModePlayer == true then
													ManualAttaching.inputToggleModePlayer = false
													vehicle:toggleMaMode()
												end
												g_inputBinding:setActionEventTextVisibility(ManualAttaching.MAEP['MA_TOGGLE_MODE_PLAYER'], true)
												g_inputBinding:setActionEventText(ManualAttaching.MAEP['MA_TOGGLE_MODE_PLAYER'], g_i18n:getText("MA_MODE_"..vehicle.ma.mode))
												if vehicle.ma.mode == 1 or vehicle.ma.mode == 3 then
													g_inputBinding:setActionEventTextVisibility(ManualAttaching.MAEP['MA_ATTACH'], true)
													for implementIndex, implement in pairs(v.spec_attacherJoints.attachedImplements) do
														if implement.object == attachable then
															if (jointDesc.ptoOutput ~= nil and jointDesc.ptoAttached == false) or attacherJoint.ptoInput == nil then
																g_inputBinding:setActionEventText(ManualAttaching.MAEP['MA_ATTACH'], g_i18n:getText("MA_DETACH"))
																local sx, sy, sz = project(px, py, pz);
																setTextAlignment(RenderText.ALIGN_CENTER);
																setTextBold(false);		
																setTextColor(0.73, 0.05, 0.05, 1.0); 
																for i=1, 10 do
																	renderText(sx, sy, 0.1, ".");
																end;												
																setTextAlignment(RenderText.ALIGN_LEFT);
																if ManualAttaching.inputAttach and (vehicle.ma.mode == 1 or vehicle.ma.mode == 3) then
																	ManualAttaching.inputAttach = false
																	v:togglePTO(attacherJointIndex, true);
																	v:detachImplement(implementIndex);
																end;
																if jointDesc.ptoOutput ~= nil and jointDesc.ptoAttached == false and attacherJoint.ptoInput ~= nil then
																	g_inputBinding:setActionEventTextVisibility(ManualAttaching.MAEP['MA_PTO_ATTACH'], true)
																	g_inputBinding:setActionEventText(ManualAttaching.MAEP['MA_PTO_ATTACH'], g_i18n:getText("MA_PTO_ATTACH"))
																	local qvx, qvy, qvz = getWorldTranslation(attacherJoint.ptoInput[1].inputNode);
																	local rvx, rvy, rvz = getWorldTranslation(jointDesc.ptoOutput[1].outputNode);
																	local sx, sy, sz = project(qvx, qvy, qvz);
																	local sx1, sy1, sz1 = project(rvx, rvy, rvz);
																	setTextAlignment(RenderText.ALIGN_CENTER);
																	setTextBold(false);		
																	setTextColor(1, 1, 0, 1.0);
																	for i=1, 10 do
																		renderText(sx, sy, 0.1, ".");
																		renderText(sx1, sy1, 0.1, ".");
																	end;													
																	setTextAlignment(RenderText.ALIGN_LEFT);
																	if ManualAttaching.inputPtoAttach and (vehicle.ma.mode == 1 or vehicle.ma.mode == 3) then
																		ManualAttaching.inputPtoAttach = false
																		playSample(ManualAttaching.sounds["attach_pto"], 1, 0.5, 0, 0, 0)
																		v:togglePTO(attacherJointIndex, true);
																	end;
																end;
															elseif jointDesc.ptoOutput ~= nil and jointDesc.ptoAttached == true and attacherJoint.ptoInput ~= nil then
																g_inputBinding:setActionEventTextVisibility(ManualAttaching.MAEP['MA_PTO_ATTACH'], true)
																g_inputBinding:setActionEventText(ManualAttaching.MAEP['MA_PTO_ATTACH'], g_i18n:getText("MA_PTO_DETACH"))
																g_inputBinding:setActionEventText(ManualAttaching.MAEP['MA_ATTACH'], g_i18n:getText("MA_DETACH"))
																local qvx, qvy, qvz = getWorldTranslation(attacherJoint.ptoInput[1].inputNode);
																local rvx, rvy, rvz = getWorldTranslation(jointDesc.ptoOutput[1].outputNode);
																local sx, sy, sz = project(qvx, qvy, qvz);
																local sx1, sy1, sz1 = project(rvx, rvy, rvz);
																setTextAlignment(RenderText.ALIGN_CENTER);
																setTextBold(false);		
																setTextColor(1, 0.23, 0, 1.0);
																for i=1, 10 do
																	renderText(sx, sy, 0.1, ".");
																	renderText(sx1, sy1, 0.1, ".");
																end;												
																setTextAlignment(RenderText.ALIGN_LEFT);
																if ManualAttaching.inputPtoAttach and (vehicle.ma.mode == 1 or vehicle.ma.mode == 3) then
																	ManualAttaching.inputPtoAttach = false
																	if attachable.spec_turnOnVehicle ~= nil then
																		attachable:setIsTurnedOn(false);
																	end
																	if attachable.spec_dischargeable ~= nil then
																		attachable:setDischargeState(0);
																	end
																	if attachable.spec_trailer ~= nil then
																		attachable:stopTipping();
																	end
																	playSample(ManualAttaching.sounds["attach_pto"], 1, 0.5, 0, 0, 0)
																	v:togglePTO(attacherJointIndex, false);
																end;
																if ManualAttaching.inputAttach and (vehicle.ma.mode == 1 or vehicle.ma.mode == 3) then
																	ManualAttaching.inputAttach = false
																	g_currentMission:showBlinkingWarning(g_i18n:getText("MA_PTO_DETACH_WARNING"), 2000);
																end
															end;
														end;
													end;
												end;
											end;
										end;
									end;
								end;
							end;
							if foundImplement ~= nil then 
								break;
							end;
						end;
					end;
				end;
			end;
			for _, implement in pairs(v.spec_attacherJoints.attachedImplements) do
				v:updateAttacherJointGraphics(implement, dt)
			end;
		end;
	end
end
function ManualAttaching:getCanToggleAttach(superFunc)
    if superFunc ~= nil then
        if not superFunc(self) then
            return false
        end
    end
	if self.ma.mode == 1 then
		return (g_currentMission.controlPlayer and g_currentMission.player ~= nil)
	elseif self.ma.mode == 2 then
		return (not g_currentMission.controlPlayer and g_currentMission.player ~= nil)
	elseif self.ma.mode ==3 then
		return true
	end
end

function ManualAttaching:isDetachAllowed(superFunc)
    if superFunc ~= nil then
        if not superFunc(self) then
            return false
        end
    end
	local attacherVehicle = nil
	local driveableVehicle = nil
	if self.spec_attachable ~= nil then
		if self.spec_attachable.attacherVehicle ~= nil then
			driveableVehicle = self:getDriveableAttacherVehicle(self.spec_attachable.attacherVehicle)
		end
	end
	if driveableVehicle ~= nil then
		attacherVehicle = driveableVehicle
	else
		if self.spec_attachable ~= nil then
			if self.spec_attachable.attacherVehicle ~= nil then
				attacherVehicle = self.spec_attachable.attacherVehicle
			end
		end
	end
	if attacherVehicle ~= nil then
		if attacherVehicle.ma ~= nil then
			if attacherVehicle.ma.mode == 1 then
				return (g_currentMission.controlPlayer and g_currentMission.player ~= nil)
			elseif attacherVehicle.ma.mode == 2 then
				return (not g_currentMission.controlPlayer and g_currentMission.player ~= nil)
			elseif attacherVehicle.ma.mode ==3 then
				return true
			end
		else
			return true
		end
	else
		return true
	end
end

function ManualAttaching:getCanBeTurnedOn(superFunc)
    if superFunc ~= nil then
        if not superFunc(self) then
            return false
        end
    end
	if self.spec_attachable ~= nil then
		if self.spec_attachable.attacherVehicle ~= nil then
			local attacherJointIndex = self.spec_attachable.attacherVehicle:getAttacherJointIndexFromObject(self)
			return true
		else
			return true
		end
	else
		return true
	end
end

function ManualAttaching:postAttach(attacherVehicle, inputJointDescIndex, jointDescIndex)
    self.avBackup = attacherVehicle;
	self.avJointDescIndex = jointDescIndex;
	local pto = attacherVehicle:getOutputPowerTakeOffsByJointDescIndex(jointDescIndex)
	if self.avBackup.avPtoOutput == nil then self.avBackup.avPtoOutput = {} end
	self.avBackup.avPtoOutput[jointDescIndex] = {}
	for _,ptoOutput in pairs(pto) do
		if ptoOutput.connectedInput ~= nil then
			table.insert(self.avBackup.avPtoOutput[jointDescIndex], {ptoOutput.connectedInput.startNode, ptoOutput.connectedInput.linkNode})
		end
	end
	self.avBackup:togglePTO(self.avJointDescIndex, attacherVehicle.spec_attacherJoints.attacherJoints[self.avJointDescIndex].ptoAttached, true);
end;

function ManualAttaching:preDetach(attacherVehicle, jointDescIndex)
	if self.avBackup ~= nil then
		self.avBackup.spec_attacherJoints.attacherJoints[self.avJointDescIndex].ptoOutput = nil
		self.avBackup:togglePTO(self.avJointDescIndex, true, true);
		self.avBackup = nil;
		self.avJointDescIndex = nil;
	end;
end;

function ManualAttaching:togglePTO(attacherJointIndex, state, noEventSend)
	TogglePTOEvent.sendEvent(self,attacherJointIndex,state,noEventSend);
	if self.spec_attacherJoints ~= nil then
		local jointDesc = self.spec_attacherJoints.attacherJoints[attacherJointIndex];
		if jointDesc ~= nil then
			if jointDesc.ptoOutput ~= nil then
				for _,ptoOutput in pairs(jointDesc.ptoOutput) do
					if ptoOutput.connectedInput ~= nil then
						setVisibility(ptoOutput.connectedInput.startNode, state);
						setVisibility(ptoOutput.connectedInput.linkNode, state);
					end
				end
			else
				for _,ptoOutput in pairs(self.avPtoOutput[attacherJointIndex]) do
					setVisibility(ptoOutput[1], state);
					setVisibility(ptoOutput[2], state);
				end
			end;
			jointDesc.ptoAttached = state;
		end;
	end;
end;

function ManualAttaching:onDraw()
end
function ManualAttaching:getDriveableAttacherVehicle(attachable)
	local attVehicle
	local tempVehicle = attachable
	--[[if attachable.spec_attachable ~= nil then
		if attachable.spec_attachable.attacherVehicle ~= nil then
			tempVehicle = attachable.spec_attachable.attacherVehicle
		end
	end]]
	while true do
		if tempVehicle.spec_drivable ~= nil then
			attVehicle = tempVehicle
			break
		else
			if tempVehicle.spec_attachable ~= nil then
				if tempVehicle.spec_attachable.attacherVehicle ~= nil then
					tempVehicle = tempVehicle.spec_attachable.attacherVehicle
				else
					attVehicle = nil
					break
				end
			else
				attVehicle = nil
				break
			end
		end
	end
	return attVehicle
end
function ManualAttaching:toggleMaMode()
	if self.ma ~= nil then
		if self.ma.mode < 3 then
			self.ma.mode = self.ma.mode + 1
		else
			self.ma.mode = 1
		end
		g_currentMission:showBlinkingWarning("MANUAL ATTACHING MODE SET TO - "..tostring(self.ma.mode), 2000);
	end
end
function ManualAttaching:actionCallback(actionName, keyStatus, arg4, arg5, arg6)
	if self:getIsActive() then
		if keyStatus > 0 then
			if actionName == 'MA_TOGGLE_MODE' then
				if self.ma.mode < 3 then
					self.ma.mode = self.ma.mode + 1
				else
					self.ma.mode = 1
				end
				g_currentMission:showBlinkingWarning("MANUAL ATTACHING MODE SET TO - "..tostring(self.ma.mode), 2000);
			elseif actionName == 'MA_TOGGLE_HELP_MENU' then
				ManualAttaching.showHelp = not ManualAttaching.showHelp
				if self.MAE ~= nil then 
					g_inputBinding:setActionEventTextVisibility(self.MAE.MA_TOGGLE_MODE.actionEventId, ManualAttaching.showHelp)
				end
			end
		elseif keyStatus == 0 then
			if actionName == 'MA_ATTACH' then
				self.ma.inputAttach = false
			elseif actionName == 'MA_PTO_ATTACH' then
				self.ma.inputPtoAttach = false
			end
		end
	end
end
function ManualAttaching:actionCallbackPlayer(actionName, keyStatus, arg4, arg5, arg6)
		if keyStatus > 0 then
			if actionName == 'MA_ATTACH' then
				ManualAttaching.inputAttach = true
			elseif actionName == 'MA_PTO_ATTACH' then
				ManualAttaching.inputPtoAttach = true
			elseif actionName == 'MA_TOGGLE_MODE_PLAYER' then
				ManualAttaching.inputToggleModePlayer = true
			end
		elseif keyStatus == 0 then
			if actionName == 'MA_ATTACH' then
				ManualAttaching.inputAttach = false
			elseif actionName == 'MA_PTO_ATTACH' then
				ManualAttaching.inputPtoAttach = false
			elseif actionName == 'MA_TOGGLE_MODE_PLAYER' then
				ManualAttaching.inputToggleModePlayer = false
			end
		end
end
function ManualAttaching:onReadStream(streamId, connection)
	if self.spec_attacherJoints ~= nil then
		if self.spec_attacherJoints.attacherJoints ~= nil then
			for k, jointDesc in pairs(self.spec_attacherJoints.attacherJoints) do
				if jointDesc.ptoOutput ~= nil then
					local state = streamReadBool(streamId)
					self:togglePTO(k, state, true);
				end;
			end;
		end;
	end;
end;
function ManualAttaching:onWriteStream(streamId, connection)
	if self.spec_attacherJoints ~= nil then
		if self.spec_attacherJoints.attacherJoints ~= nil then
			for k, jointDesc in pairs(self.spec_attacherJoints.attacherJoints) do
				if jointDesc.ptoOutput ~= nil then
					streamWriteBool(streamId, jointDesc.ptoAttached);
				end;
			end;
		end;
	end;
end;
TogglePTOEvent = {};
TogglePTOEvent_mt = Class(TogglePTOEvent, Event);

InitEventClass(TogglePTOEvent, "TogglePTOEvent");

function TogglePTOEvent:emptyNew()
    local self = Event:new(TogglePTOEvent_mt);
    self.className="TogglePTOEvent";
    return self;
end;

function TogglePTOEvent:new(object, attacherInd, state)
	local self = TogglePTOEvent:emptyNew()
	self.object = object;
	self.attacherInd = attacherInd;
	self.state = state;
	return self;
end;

function TogglePTOEvent:readStream(streamId, connection)
	self.object = NetworkUtil.readNodeObject(streamId);
	self.attacherInd = streamReadInt8(streamId);
    self.state = streamReadBool(streamId);
    self:run(connection);
end;

function TogglePTOEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.object);
	streamWriteInt8(streamId, self.attacherInd);
	streamWriteBool(streamId, self.state);
end;

function TogglePTOEvent:run(connection)
	self.object:togglePTO(self.attacherInd,self.state, true);
	if not connection:getIsServer() then
		g_server:broadcastEvent(TogglePTOEvent:new(self.object, self.attacherInd, self.state), nil, connection, self.object);
	end;
end;

function TogglePTOEvent.sendEvent(vehicle, attacherInd, state, noEventSend)
	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			g_server:broadcastEvent(TogglePTOEvent:new(vehicle, attacherInd, state), nil, nil, vehicle);
		else
			g_client:getServerConnection():sendEvent(TogglePTOEvent:new(vehicle, attacherInd, state));
		end;
	end;
end;