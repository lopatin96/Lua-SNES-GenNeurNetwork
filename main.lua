math.randomseed(os.time())

dofile("luaneural.lua")
Filename = "SMB1-1.state"

controller = {}
buttons = {}
function setUpButtons()
	buttons["A"] = 0 -- JUMP 1
	buttons["B"] = 0 -- Faster
	buttons["X"] = 0
	buttons["Y"] = 0
	buttons["Up"] = 0
	buttons["Down"] = 0
	buttons["Left"] = 0
	buttons["Right"] = 0
end

function clearJoypad()
	controller = {}
	for k, v in pairs(buttons) do
		controller["P1 " .. k] = false
	end
	joypad.set(controller)
end

function setUpJoypad(position, genome)
	controller = {}
	if genome[position.current.x] ~= nil then
		if buttons[genome[position.current.x].action] <= 0 then 
			controller["P1 " .. genome[position.current.x].action] = true
			buttons[genome[position.current.x].action] = genome[position.current.x].pressingForce
		end
	end
	for k, v in pairs(buttons) do
		if v > 0 then
			controller["P1 " .. k] = true
			local d = v - 1
			buttons[k] = d
		end
	end
	controller["P1 " .. dominantsNeurons[1]] = true
	joypad.set(controller)
end

function updateMarioPosition(position)
	local currentX = memory.readbyte(0x6D) * 0x100 + memory.readbyte(0x86)
	local currentY = memory.readbyte(0x03B8)+16
	
	position.previous.x = position.current.x
	position.previous.y = position.current.y
	
	position.current.x = currentX
	position.current.y = currentY
end

function restart()
	savestate.load(Filename)
end

function isStuck(l_numberOfStuckFrame, position)
	if position.previous.x == position.current.x then
		numberOfStuckFrame = l_numberOfStuckFrame + 1
		if buttons[dominantsNeurons[2]] == 0 then
			buttons[dominantsNeurons[2]] = 40
		end
	else
		numberOfStuckFrame = 0
	end
	
	if numberOfStuckFrame >= numberOfFrameToDetectStuck or position.current.y > 192 then
		numberOfStuckFrame = 0
		return true
	end
	
	return false
end

function drawDebugDetails(position, fitness, index, generation)
	positionString  = string.format("current position = (%s, %s)", position.current.x, position.current.y)
	gui.drawText(1, 1, positionString)
	positionString  = string.format("Fitness (current: %s, max: %s)", fitness.current, fitness.maximum)
	gui.drawText(1, 20,  positionString)
	positionString  = string.format("Generation: %s; Genome: %s", generation.index, index)
	gui.drawText(1, 40,  positionString)
	gui.drawText(1, 60, "Stuck: " .. numberOfStuckFrame .. "; Pressure: " .. buttons[dominantsNeurons[2]])
	gui.drawText(1, 80, "BFFG: " .. bestFitnessForGeneration)
end

function updateGui(debugMode, index, generation, genome)
	if forms.ischecked(hideBanner) then
		debugMode = false
	else
		debugMode = true
	end
		
	if debugMode then 
		drawDebugDetails(position, fitness, index, generation)
	end
end

function getFitness(position)
	return position.current.x
end

function updateFitness(position, fitness)
	fitness.current = getFitness(position)
	if fitness.maximum < fitness.current then
		fitness.maximum = fitness.current
	end
end

function checkIfMarioIsStuck()
	if isStuck(numberOfStuckFrame, position) then
		restart()
	end
end

function findDominantsNeurons(buttons)
	restart()
	local maxFitness = 0
	updateMarioPosition(position)
	local maxYGlobal = position.current.y
	local maxYCurrent = maxYGlobal
	
	for k, v in pairs(buttons) do
		local currentFitness = 0
		clearJoypad()
		
		while true do
			updateMarioPosition(position)
			maxYCurrent = position.current.y
			controller["P1 " .. k] = true
			joypad.set(controller)
			if isStuck(numberOfStuckFrame, position) then
				break
			end
			
			if maxYGlobal > maxYCurrent then
				maxYGlobal = maxYCurrent
				dominantsNeurons[2] = k
			end
			
			emu.frameadvance()
		end
		
		if maxFitness < getFitness(position) then
			maxFitness = getFitness(position)
			dominantsNeurons[1] = k
		end
		
		restart()
	end
	fitness.maximum = maxFitness
end

function generateANeuron(neuron)
	return {action=dominantsNeurons[2], pressingForce=math.random(0, pressingForce)}
end

function generateAGenome(lengthOfStep, position)
	local genome = {}
	for i=40, math.floor(fitness.maximum)+lengthOfStep*5, math.floor(lengthOfStep) do
		genome[i] = generateANeuron(dominantsNeurons[1])
		
		if genome[i-lengthOfStep] ~= nil then
			local p = genome[i-lengthOfStep].pressingForce / 5.625
			local value = nil
			if     p <= 5.625  then value = network:forewardPropagate(0,0,0)[1]
			elseif p <= 11.25  then value = network:forewardPropagate(0,0,1)[1]
			elseif p <= 16.875 then value = network:forewardPropagate(0,1,0)[1]
			elseif p <= 22.5   then value = network:forewardPropagate(0,1,1)[1]
			elseif p <= 28.125 then value = network:forewardPropagate(1,0,0)[1]
			elseif p <= 33.75  then value = network:forewardPropagate(1,0,1)[1]
			elseif p <= 39.375 then value = network:forewardPropagate(1,1,0)[1]
			else                    value = network:forewardPropagate(1,1,1)[1]
			end
			genome[i].pressingForce = math.floor(genome[i].pressingForce * value)
		end
		
		record = i
	end
	return genome
end

function generateFirstPopulation(sizeOfPopulation)
	local population = {}
	for i=1, sizeOfPopulation do
		table.insert(population, generateAGenome(lengthOfStep, position))
	end
	
	return population
end

function shuffle(tbl)
  local size = #tbl
  for i = size, 1, -1 do
    local rand = math.random(size)
    tbl[i], tbl[rand] = tbl[rand], tbl[i]
  end
  return tbl
end

function selectedGenomes(genomes)
	-- sort the genomes in descending order
	table.sort(genomes, function (left, right)
		return left[1] > right[1]
	end)
	
	local result = {}
	for i=1, best_sample*sizeOfPopulation do
		table.insert(result, genomes[i][2])
	end
	
	for i=1, 1 do -- todo
		r = math.random(1, #genomes)
		table.insert(result, genomes[r][2])
	end
	shuffle(result)
	
	return result
end

function getTail()
	local tail = {}
	if record < fitness.maximum then
		for i=record+lengthOfStep, math.floor(fitness.maximum)+lengthOfStep*5, math.floor(lengthOfStep) do
			tail[i] = generateANeuron(dominantsNeurons[1])
			last_record = i
		end
	end
	return tail
end

function glueTail(child_l)
	local chaild_ll = child_l
	local tail = getTail()
	for k, v in pairs(tail) do
		chaild_ll[k] = v
	end
	return chaild_ll
end

function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function createChild(individual1, indiidual2, percent)
	local child_l = deepcopy(individual1)
	for k, v in pairs(indiidual2) do
		if math.random() < percent then
			child_l[k] = indiidual2[k] -- {action="A", pressingForce=110}
		end
	end
	child_l = glueTail(child_l)
	
	return child_l
end

function createChildren(breeders, numberOfChildren)
	local nextPopulation = {}
	for i=1, tonumber(#breeders/2) do
		for j=1, numberOfChildren do
			table.insert(nextPopulation, createChild(breeders[i], breeders[#breeders-i+1], (j-1)*(1/(numberOfChildren-1))))
		end
	end
	
	return nextPopulation
end

function mutateGenome(genome)
	local mutatedGenome = deepcopy(genome)
	for i=last_record, (last_record - (16*lengthOfStep)), -lengthOfStep do
		mutatedGenome[i] = generateANeuron(dominantsNeurons[1])
	end
	for i=(last_record - (17*lengthOfStep)), (last_record - (25*lengthOfStep)), -lengthOfStep do
		if math.random() < chance_of_neuron_mutation then
			mutatedGenome[i] = generateANeuron(dominantsNeurons[1])
		end
	end
	return mutatedGenome
end

function mutatePopulation(population, chance_of_mutation)
	local mutatedPopulation = {}
	for i=1, #population do
		if math.random() < chance_of_mutation then -- < 0 then
			mutatedPopulation[i] = mutateGenome(population[i])
		else
			mutatedPopulation[i] = population[i]
		end
	end
	
	return mutatedPopulation
end

function nextGeneration(generation, nextPopulation)
	generation.index = generation.index + 1
	generation.population = nextPopulation
	record = last_record
end

function trainNeuralNetwork()
	local attempts = 100 -- number of times to do backpropagation
	for i = 1,attempts do
		network:backwardPropagate({0,0,0},{vectorAction[1]})
		network:backwardPropagate({0,0,1},{vectorAction[2]})
		network:backwardPropagate({0,1,0},{vectorAction[3]})
		network:backwardPropagate({0,1,1},{vectorAction[4]})
		network:backwardPropagate({1,0,0},{vectorAction[5]})
		network:backwardPropagate({1,0,1},{vectorAction[6]})
		network:backwardPropagate({1,1,0},{vectorAction[7]})
		network:backwardPropagate({1,1,1},{vectorAction[8]})
	end
end

function adjustVectorAction(bestFitnessForGeneration, fitnessMaximum)
	if bestFitnessForGeneration < fitnessMaximum then
		for i=1, #vectorAction do
			vectorAction[i] = math.random(0, 1)
		end
	end
end

function updateBestFitnessForGeneration(bestFitnessForGeneration, fitnessCurrent)
	if bestFitnessForGeneration < fitnessCurrent then
		return fitnessCurrent
	end
	return bestFitnessForGeneration
end

network = NeuralNetwork.create(3, 1, 1, 4, 0.3) -- NerualNetwork.create(numInputs, numOutputs, numHiddenLayers, neuronsPerLayer, learningRate)
vectorAction = {0, 0, 0, 0, 1, 1, 1, 0}
setUpButtons()
pressingForce = 45
position = {previous={x=0, y=0}, current={x=0, y=0}}
fitness = {current=0, maximum=0}
numberOfStuckFrame = 0
numberOfFrameToDetectStuck = 100
dominantsNeurons = {}
findDominantsNeurons(buttons)
lengthOfStep = 16
record = 0
last_record = 0
sizeOfPopulation = 20
generation = {index=0, population=generateFirstPopulation(sizeOfPopulation)}
best_sample = 0.4
lucky_few = 0.1
numberOfChildren = 4
chance_of_mutation = 0.5
chance_of_neuron_mutation = 0.2

form = forms.newform(200, 100, "Settings")
hideBanner = forms.checkbox(form, "Hide", 5, 25)

bestFitnessForGeneration = 0

while true do
	result = {}
	trainNeuralNetwork()
	bestFitnessForGeneration = 0
	for i=1, #generation.population do
		genome = generation.population[i]
		while true do
			clearJoypad()
			updateGui(debugMode, i, generation, genome)
			updateMarioPosition(position)
			updateFitness(position, fitness)
			if isStuck(numberOfStuckFrame, position) then
				break
			end
			setUpJoypad(position, genome)
			emu.frameadvance()	
		end
		bestFitnessForGeneration = updateBestFitnessForGeneration(bestFitnessForGeneration, fitness.current)
		table.insert(result, {fitness.current, genome})
		restart()
	end
	adjustVectorAction(bestFitnessForGeneration, fitness.maximum)
	genomes = {}
	genomes = selectedGenomes(result)
	nextPopulation = createChildren(genomes, numberOfChildren)
	mutatedPopulation = mutatePopulation(nextPopulation, chance_of_mutation)
	nextGeneration(generation, mutatedPopulation)
end