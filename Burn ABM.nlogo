breed [suprabasal-ktns suprabasal-ktn]
breed [basal-ktns basal-ktn]
breed [ecms ecm]
breed [fibroblasts fibroblast]
breed [capillaries capillary]
breed [platelets platelet]
breed [neutrophils neutrophil]
breed [macrophages macrophage]
breed [mast-cells mast-cell]


turtles-own [tick-stagger priority] ;; 'priority' is used to determine which cells can displace other cells. Cells of higher priority (lower value) can displace cells of lower priority, but not vice-versa
                                    ;; 'tick-stagger' adds stochasticity. staggers when agents perform actions
suprabasal-ktns-own [ injury-counter]
basal-ktns-own [ vert-mitosis-rate hor-mitosis-rate ] ;mitotic rate defined as 'rate' divisions per 100 ticks
capillaries-own [ permeability blood-flow-rate num-neuts-to-hatch num-macs-to-hatch]
fibroblasts-own [ migration-rate ecm-production-rate injury-level]
platelets-own [ time-alive]
neutrophils-own [ time-in-cap location lifespan time-alive]
macrophages-own [ time-in-cap location lifespan time-alive]

patches-own [ patch-type egf-level pdgf-level il1-level fgf-level tnf-a-level il6-level vegf-level tgf-b-level bradykinin-level txa2-level]

globals [ amt-ecm-burned amt-ecm-produced percent-ecm-reproduced reepithelialization-progress max-recursion-depth time-of-burn basal-layer-ycor]



;; Timescale is 1 tick per minute
to setup
  clear-all
  if RandomRuns? = false [random-seed RandomSeed]

  ;; Creates the world
  set-patch-size unit-size * 3 / 12 ;; unit-size is an input in the interface and is in microns. it is the size of 1 patch. unit-size of 20 means 1 patch is 20microns x 20microns
  resize-world 0 ((num-hair-follicles * 1000 / unit-size) - 1) 0 ((3000 / unit-size) - 1) ;;resizes the world based off of number of hair follicles and unit-size
  set max-recursion-depth 20 ;; prevenst 'recursion too deep' errors

  ;; Sets up the basal layer
  set basal-layer-ycor round(max-pycor * 0.85)
  ask patches with [pycor = basal-layer-ycor] [
    sprout-basal-ktns 1 [set priority -1 set shape "square" set tick-stagger random 360 set color 61 + min (list (vert-mitosis-rate * 10 + hor-mitosis-rate * 10)  8)]
  ]

  ;;Sets up suprabasal keratinocytes
  ask patches with [pycor > basal-layer-ycor and pycor < basal-layer-ycor + 10][sprout-suprabasal-ktns 1 [set priority 2 set shape "square"  set tick-stagger (random 2880) set color 34 + random-float 2]]

  ;; Sets up fibroblasts
  ask patches with [pycor < basal-layer-ycor - 1][if not (any? fibroblasts in-radius 5) and not any? turtles-here [sprout-fibroblasts 1 [set migration-rate 0 set ecm-production-rate 0 set priority -2  set shape "square" set color 107]]]

  ;; Sets up capillaries
  ask patches with [pycor < basal-layer-ycor - 1][if not (any? capillaries in-radius 8) and not any? turtles-here [sprout-capillaries 1 [set tick-stagger random 360 set priority -2  set shape "circle" set color red]]]

  ;; Sets up the ECM
  ask patches with [pycor < basal-layer-ycor][sprout-ecms 1 [set priority 0 set shape "square" set color 3]]

  ;; Sets up the hair follicles
  create-hair-follicles

  reset-ticks
end

;; Creates the correct number of hair follicles
to create-hair-follicles
  foreach (range 0 num-hair-follicles) [
    x -> let follicle-position round max-pxcor * 1 / (num-hair-follicles * 2) * (2 * x + 1)

    ask turtles with [pxcor >= follicle-position - 5 and pxcor < follicle-position + 5 and pycor > 0.1 * max-pycor] [die]
    ask turtles with [pxcor >= follicle-position - 7 and pxcor < follicle-position + 7 and pycor > 0.1 * max-pycor and pycor < 0.1 * max-pycor + 15] [die] ;; for the bulb section, which is slightly wider

    ask ecms with [any? neighbors with [not any? turtles-here]] [ ask neighbors with [not any? turtles-here] [ sprout-basal-ktns 1 [
      set priority -1 set shape "square"
      set tick-stagger random 360  ;; tick-stagger used so not all basal cells mitose at the same exact time
      set color 61 + min (list (vert-mitosis-rate * 10 + hor-mitosis-rate * 10)  8)
    ] ] ]
  ]

  ask patches with [pycor < basal-layer-ycor + 10] [if (not any? turtles-here) [sprout-suprabasal-ktns 1[set priority 2 set shape "square"  set color 34 + random-float 2 set tick-stagger random 2880]]]
end

to go
  if epithelialization [   ;; epithelization is a switch in the interface
    ask basal-ktns [basal-ktn-function]
    ask suprabasal-ktns [suprabasal-ktn-function]
  ]

  if vascular [ ;;vascular is a switch in the interface
    ask capillaries [capillary-function]
    ask platelets [platelet-function]
    undergo-angiogenesis
  ]

  if inflammation [   ;;inflammation/proliferation is a switch in the interface
    ask neutrophils [neutrophil-function]
    ask macrophages [macrophage-function]
  ]
  if proliferation [ ;;proliferation is a switch in the interface
    ask fibroblasts [fibroblast-function]
  ]

  update-chemokine-gradient
  check-reepithelialization-and-ecm-progress

  if debridement [ ;;debridement is a switch in the interface
    if ticks = 2880 or ticks = 5760 or ticks = 8640 [ debride ]    ;; debrides on day 2, 4, and 6
  ]

  if ticks = (1440 * num-days-to-simulate) [ stop ] ;;num-days-to-simulate is an input in the interface

  tick
end


to burn
  let starting-amt-ecm count ecms
  ;if unit size is 15 (1 patch = 15 microns, then 1mm burn depth is 1000 / 15
  set time-of-burn ticks
  let burn-depth round (1000 / unit-size) ;; creates a 1mm burn based off size of unit. depth is relative to most superficial suprabasal keratinocyte layer
  let burn-bottom basal-layer-ycor + 10 - burn-depth

  ask turtles with [ycor > burn-bottom] [die]

  ask patches with [pycor > burn-bottom] [sprout-platelets 1 [ set color 13 set tick-stagger random 5760 set priority 3]]

  ask suprabasal-ktns [ set injury-counter 10080 ] ;; injures the keratinocytes

  let zone-of-stasis-y-max burn-bottom
  let zone-of-stasis-y-min zone-of-stasis-y-max - max-pycor * 0.25

  ask fibroblasts [ set injury-level (100 - (burn-bottom - ycor)) ] ;; injures fibroblasts

  let zone-hyperemia-ymax zone-of-stasis-y-min
  let zone-hyperemia-ymin 0
  set amt-ecm-burned starting-amt-ecm - (count ecms) ;; tracks how much ecm/dermis was destroyed
end

;; Debridement is implemented essentially as a small "burn" without destroying any tissue
to debride
  let x-range (range 0 (max-pxcor + 1))
  foreach x-range [
    ;; Kills only the platelet layer above the most superficial cell type
    x -> let highest-permanent max-one-of (turtles with [xcor = x and priority <= 2]) [ycor]
    let highest-perm-y ([ycor] of highest-permanent)
    ask turtles with [xcor = x and ycor > highest-perm-y] [die]

    ask patches with [not (any? turtles-here) and pxcor = x and pycor < highest-perm-y + 20] [sprout-platelets 1 [ set color 13 set tick-stagger random 5760 set priority 3]] ;;creates a smaller platelet plug
  ]

  ask suprabasal-ktns [ set injury-counter 7200 ] ;; lightly injures the keratinocytes
end

to check-reepithelialization-and-ecm-progress
  if not (ticks = 0) and ticks mod 720 = 0 [              ;;check progress half day to improve run times
    set reepithelialization-progress 0
    let num-basalktns 0
    let x-range (range 0 (max-pxcor + 1))
    foreach x-range [
      x ->  let basalktn-at-x one-of (basal-ktns with [xcor = x])

      ifelse not (basalktn-at-x = nobody) [
        set num-basalktns num-basalktns + 1
      ] [
        print basalktn-at-x
      ]
    ]
    set reepithelialization-progress (num-basalktns / (max-pxcor + 1)) * 100
  ]

  if not (time-of-burn = 0) [
    set percent-ecm-reproduced (amt-ecm-produced / amt-ecm-burned) * 100
  ]
end

to undergo-angiogenesis
  ask patches with [any? ecms-here] [
    let chance-of-angiogenesis 1 + random 100
    if chance-of-angiogenesis < vegf-level and not (any? capillaries in-radius 8) and not (any? fibroblasts-here) [
      sprout-capillaries 1 [ set tick-stagger random 360 set priority -2  set shape "circle"]
    ]
  ]
end

to capillary-function
  let base-cap-blood-flow-rate 1.2 ;; # of times inflam. cells can pass through per 60 ticks (per hour)
  let base-cap-permeability 1 ;;defined as % likelihood a cell can extravasate each tick

  set blood-flow-rate max (list 0 (base-cap-blood-flow-rate - txa2-level * 1000))
  set size max (list 0.5 blood-flow-rate ) ;; to visualize flow rate

  ;; permeability defined as % chance a neutrophil can extravasate into surrounding ecm each tick
  set permeability min (list 25 (base-cap-permeability + round (vegf-level / 1)))  ;;make max permeaibliyt 25%, otherwise way too many cells in the system
  set color 15 + (4 * permeability / 50)


  set num-neuts-to-hatch 0 + min (list 6 round (pdgf-level  * 10000 )) + min (list 0.6 (il6-level * 1000))  ; chances # of neutrophilic recruitment based off of pdgf and il6 levels
  set num-macs-to-hatch 0 + min (list 1.5 round (pdgf-level * 10000 )) + min (list 0.15 (il6-level * 1000)) ; chances # of macrophage recuritmnet based off of pdgf and il6 levels

  let net-rate-neuts blood-flow-rate * num-neuts-to-hatch
  let net-rate-macs blood-flow-rate * num-macs-to-hatch

  if net-rate-neuts > 0 [
    if ((ticks + tick-stagger) mod ceiling (60 / net-rate-neuts)) = 0  [
      hatch-neutrophils 1[set lifespan (7200 + random 500) set priority 0  set shape "star" set size 0.7 set color yellow set time-in-cap 0 set location "capillary" set tick-stagger random 360]
    ]
  ]
  if net-rate-macs > 0 [
     if ((ticks + tick-stagger) mod ceiling (60 / net-rate-macs)) = 0  [
      hatch-macrophages 1 [set lifespan (7200 + random 500) set priority 0 set shape "circle" set size 0.5 set color yellow set time-in-cap 0 set location "capillary" set tick-stagger random 360]
    ]
  ]
end

to platelet-function
  set time-alive time-alive + 1
  let pdgf-release-amt max (list 0 (500000 - (time-alive + tick-stagger) * 80 ))
  let txa2-release-amt max (list 0 (500000 - (time-alive + tick-stagger) * 80 ))
  set pdgf-level pdgf-level + pdgf-release-amt
  set txa2-level txa2-level + txa2-release-amt

  if pdgf-release-amt = 0 and txa2-release-amt = 0 [
    set color 11 ;; visual representation of inactive platelet
  ]
end



to neutrophil-function
  if location = "capillary" [
    if time-in-cap > 1 [die]
    let cap one-of capillaries-here
    if not (cap = nobody) [
      if random 100 < [permeability] of cap [   ;; converts permeability into the actual percent likelihood
        let new-location one-of neighbors with [any? ecms-here and not any? fibroblasts-here and not any? neutrophils-here and not any? macrophages-here and not any? capillaries-here]
        if not (new-location = nobody) [ move-to new-location set location "wound-bed"]
      ]
    ]
    set time-in-cap time-in-cap + 1
  ]

  if location = "wound-bed" [
    set il6-level il6-level + 0.15
    if (ticks + tick-stagger) mod 10 = 0 [   ;; neutrophil moves every 2 hour

      let p1 max-n-of 3 neighbors [pdgf-level]
      let p one-of p1 with [any? ecms-here and not any? fibroblasts-here and not any? neutrophils-here and not any? macrophages-here and not any? capillaries-here]

      let i1 max-n-of 3 neighbors [il6-level]
      let i one-of i1 with [any? ecms-here and not any? fibroblasts-here and not any? neutrophils-here and not any? macrophages-here and not any? capillaries-here]

      ifelse not (p = nobody) [
        ifelse ([pdgf-level] of p > pdgf-level) and ([pycor] of p >= ycor) [
          move-to p
        ] [
          move-to one-of (neighbors with [any? ecms-here and not any? fibroblasts-here and not any? neutrophils-here and not any? macrophages-here and not any? capillaries-here])
        ]
      ] [
        let rando-neighbor one-of (neighbors with [any? ecms-here and not any? fibroblasts-here and not any? neutrophils-here and not any? macrophages-here and not any? capillaries-here])
        if not (rando-neighbor = nobody) [ move-to rando-neighbor]
      ]
    ]

    if ticks mod 120 = 0 and (random 100) < 100[
      let platelet-patch one-of neighbors with [any? platelets]
      if not (platelet-patch = nobody)  [ ask platelets-on platelet-patch [ die]]
    ]

  ]
  set time-alive time-alive + 1
  if time-alive > lifespan [ die ]
end

to macrophage-function
  set vegf-level vegf-level + 10
  set tgf-b-level tgf-b-level + 10;100000
  set tnf-a-level tnf-a-level + 4
  set egf-level egf-level + 10

  if location = "capillary" [
    if time-in-cap > 1 [die]
    let cap one-of capillaries-here
    if not (cap = nobody) [
      if random 100 < [permeability] of cap [   ;; converts permeability into the actual percent likelihood
        let new-location one-of neighbors with [any? ecms-here and not any? fibroblasts-here and not any? neutrophils-here and not any? macrophages-here and not any? capillaries-here]
        if not (new-location = nobody) [ move-to new-location set location "wound-bed"]
      ]
    ]
    set time-in-cap time-in-cap + 1
  ]

  if location = "wound-bed" [
    if (ticks + tick-stagger) mod 10 = 0 [  ;; mac moves once every 2 hours

      let p1 max-n-of 3 neighbors [pdgf-level]
      let p one-of p1 with [any? ecms-here and not any? fibroblasts-here and not any? neutrophils-here and not any? macrophages-here and not any? capillaries-here]

      let i1 max-n-of 3 neighbors [il6-level]
      let i one-of i1 with [any? ecms-here and not any? fibroblasts-here and not any? neutrophils-here and not any? macrophages-here and not any? capillaries-here]

      ifelse not (p = nobody) [
        ifelse ([pdgf-level] of p > pdgf-level) and ([pycor] of p >= ycor) [
          move-to p
        ] [
          move-to one-of (neighbors with [any? ecms-here and not any? fibroblasts-here and not any? neutrophils-here and not any? macrophages-here and not any? capillaries-here])
        ]
      ] [
        let rando-neighbor one-of (neighbors with [any? ecms-here and not any? fibroblasts-here and not any? neutrophils-here and not any? macrophages-here and not any? capillaries-here])
        if not (rando-neighbor = nobody) [ move-to rando-neighbor]
      ]
    ]
    if ticks mod 120 = 0 and (random 100) < 100 [     ;;mac has 25% chance of phagocytosing nearby debris (in this case, platelet particles) every hour
      let platelet-patch one-of neighbors with [any? platelets]
      if not (platelet-patch = nobody)  [ ask platelets-on platelet-patch [ die]]
    ]

  ]

  set time-alive time-alive + 1
  if time-alive > lifespan [ die ]
end

to basal-ktn-function
  let base-vert-mitosis-rate 0.1
  let base-hor-mitosis-rate 0

  set hor-mitosis-rate min (list 0.06 (base-hor-mitosis-rate + il6-level * 0.02 + egf-level * 1 + tnf-a-level * 0.001)) ; 0.05 used as max rate of division of ESC to be once every 20 hours ish. can lower to 0.01
  set vert-mitosis-rate min (list 0.1 (base-vert-mitosis-rate + il6-level * 0.001 + tnf-a-level * 0.001))


  set color 61 + min (list (vert-mitosis-rate * 10 + hor-mitosis-rate * 10)  8) ;; changes color of basal cell based off of mitotic rate (whiter for higher rates)

  vert-mitosis vert-mitosis-rate
  hor-mitosis hor-mitosis-rate
end

to suprabasal-ktn-function
;  if injury-level < 50 and injury-level > 0  [
  ;if injury-level > 0  [
  if injury-counter > 0 + tick-stagger [
    set egf-level egf-level + 0.5
    set tnf-a-level tnf-a-level + 1
    set il6-level il6-level + 0.5

    set il1-level il1-level + 1
    set fgf-level fgf-level + 1

    set vegf-level vegf-level + 0.3
    set injury-counter injury-counter - 1
  ]

end

to fibroblast-function
  if injury-level > 60 [ set color 92]
  set migration-rate min (list 0.8 (pdgf-level * 0.01 + tgf-b-level * 10 + fgf-level * 0.1 + il1-level * 0.1 + tnf-a-level * 0.1)) ;; migration rate is units moved in 1 hour, or 60 ticks
  set ecm-production-rate min (list 1.4 (pdgf-level * 1000 + tgf-b-level * 0.02 + fgf-level * 0.01 + il1-level * 0.01 + tnf-a-level * 0.01))   ;;production rate is units ecm made in 1 hour, or 60 ticks

  if not (injury-level > 60) [
    if not (migration-rate = 0) [ ;;prevent divide by 0 error
      if (ticks mod (max (list 1 round (60 / migration-rate)))) = 0 [

        let p1 max-n-of 3 neighbors [pdgf-level]
        let p one-of p1 with [any? ecms-here and not ((count fibroblasts in-radius 2) > 1 ) and not any? capillaries-here and not any? macrophages-here and not any? neutrophils-here]

        let t1 max-n-of 3 neighbors [tgf-b-level]
        let t one-of t1 with [any? ecms-here and not ((count fibroblasts in-radius 2) > 1 ) and not any? capillaries-here and not any? macrophages-here and not any? neutrophils-here]


        if not (p = nobody) and any? ecms-on p [
          let old-patch patch-here
          ifelse [pdgf-level] of p > pdgf-level [move-to p] [
            if not (t = nobody) and any? ecms-on t [
              if [tgf-b-level] of t > tgf-b-level [ move-to t]
            ]
          ]
        ]
      ]
    ]

    let curr-priority priority

    if not (ecm-production-rate = 0) [
      if (ticks mod (max (list 1 round (60 / ecm-production-rate)))) = 0 [

        let curr-x xcor
        let curr-y ycor
        let random-neighbor one-of neighbors with [not any? turtles-here]
        if random-neighbor = nobody [
          set random-neighbor one-of neighbors with [not any? basal-ktns-here and not any? turtles-here with [priority < curr-priority] and
            not any? platelets-here and not any? suprabasal-ktns-here]

          ;; so fibroblasts produce only upwards
          if not (random-neighbor = nobody) [
            if any? ecms-on random-neighbor [

              ask ecms-on random-neighbor [displace-randomly-ecm curr-x curr-y]
            ]

            if not any? ecms-on random-neighbor [
              hatch-ecms 1 [set priority 0 set shape "square" set color gray move-to random-neighbor]
              set amt-ecm-produced amt-ecm-produced + 1
            ]
          ]
        ]
      ]
    ]
  ]
end

to displace-randomly-ecm [prior-x prior-y]
  let curr-priority priority
  let curr-y ycor
  let curr-x xcor

  let dir-x (curr-x - prior-x)
  let dir-y (curr-y - prior-y)
  if dir-y = 0 and dir-x = 0 [ stop ]
  let dir-angle atan dir-y  dir-x

  let new-a-0 dir-angle - 90
  let new-a-1 dir-angle - 45
  let new-a-2 dir-angle + 0
  let new-a-3 dir-angle + 45
  let new-a-4 dir-angle + 90

  let n1x round (cos new-a-1) + curr-x
  let n1y round (sin new-a-1) + curr-y
  let n2x round (cos new-a-2) + curr-x
  let n2y round (sin new-a-2) + curr-y
  let n3x round (cos new-a-3) + curr-x
  let n3y round (sin new-a-3) + curr-y


  let random-neighbor one-of neighbors with [not any? turtles-here and
    ((pxcor = n1x and pycor = n1y) or (pxcor = n2x and pycor = n2y) or (pxcor = n3x and pycor = n3y))]
  if random-neighbor = nobody [
    set random-neighbor one-of neighbors with [not any? turtles-here with [priority < curr-priority] and
      ((pxcor = n1x and pycor = n1y) or (pxcor = n2x and pycor = n2y) or (pxcor = n3x and pycor = n3y))]
  ]
  if not (random-neighbor = nobody) [
    if any? ecms-on random-neighbor [
      ask ecms-on random-neighbor [displace-randomly-ecm curr-x curr-y]
    ]
    if any? platelets-on random-neighbor [ ask platelets-on random-neighbor [die]]
    if any? suprabasal-ktns-on random-neighbor [ ask suprabasal-ktns-on random-neighbor [die]]
    if not any? ecms-on random-neighbor [
      move-to random-neighbor
    ]
  ]
end


to vert-mitosis [ rate ]     ;; called by basal-ktns to create suprabasal-ktns
  if rate = 0 [ stop ] ;; prevents divide by 0 error

  if ((ticks + tick-stagger) mod ceiling (60 / rate)) = 0 [
    let curr-priority priority
    let curr-x xcor
      let curr-y ycor
    let random-neighbor one-of neighbors with [not any? turtles-here]
    if random-neighbor = nobody [
      set random-neighbor one-of neighbors with [not any? ecms-here and not any? turtles-here with [priority  <= curr-priority]]  ;; should be: priority <= curr-priority. the line "not any? ecms-here" prevents mitosis into the dermis
    ]
    if not (random-neighbor = nobody) [
      if any? turtles-on random-neighbor [
        let recursion-depth 0
        ask turtles-on random-neighbor [displace-randomly curr-x curr-y recursion-depth]
      ]
      if any? platelets-on random-neighbor [ ask platelets-on random-neighbor [die]]
      if not any? turtles-on random-neighbor [
          hatch-suprabasal-ktns 1 [set priority 2 set shape "square" set color 34 + random-float 2 set tick-stagger (random 2880) move-to random-neighbor ]
      ]
    ]
  ]
end

to displace-randomly [ prior-x prior-y recursion-depth]     ;; called by both vert-mitosis and hor-mitosis to displace cells in the way in a random but directional manner
  let curr-priority priority
  let curr-y ycor
  let curr-x xcor

  let rec-depth recursion-depth + 1

  let dir-x (curr-x - prior-x)
  let dir-y (curr-y - prior-y)
  if dir-y = 0 and dir-x = 0 [ stop ]
  let dir-angle atan dir-y  dir-x

  let new-a-0 dir-angle - 90
  let new-a-1 dir-angle - 45
  let new-a-2 dir-angle + 0
  let new-a-3 dir-angle + 45
  let new-a-4 dir-angle + 90


  let n1x round (cos new-a-1) + curr-x
  let n1y round (sin new-a-1) + curr-y
  let n2x round (cos new-a-2) + curr-x
  let n2y round (sin new-a-2) + curr-y
  let n3x round (cos new-a-3) + curr-x
  let n3y round (sin new-a-3) + curr-y

  let random-neighbor one-of neighbors with [not any? turtles-here and
    ((pxcor = n1x and pycor = n1y) or (pxcor = n2x and pycor = n2y) or (pxcor = n3x and pycor = n3y))]
  if random-neighbor = nobody [
    set random-neighbor one-of neighbors with [not any? turtles-here with [priority < curr-priority] and
        ((pxcor = n1x and pycor = n1y) or (pxcor = n2x and pycor = n2y) or (pxcor = n3x and pycor = n3y))]
  ]
  if not (random-neighbor = nobody) [
    if any? turtles-on random-neighbor [
      if rec-depth < max-recursion-depth [
        ask turtles-on random-neighbor [displace-randomly curr-x curr-y rec-depth]
      ]
    ]
    if any? platelets-on random-neighbor [ ask platelets-on random-neighbor [die]]
    if not any? turtles-on random-neighbor [
      move-to random-neighbor
    ]
  ]
end

to hor-mitosis [ rate ]     ;; called by basal-ktns to create new basal-ktns
  if rate = 0 [ stop ]

  if ((ticks + tick-stagger) mod ceiling (60 / rate)) = 0 [
    let curr-priority priority
    let curr-x xcor
    let curr-y ycor

    let possible one-of neighbors4 with [not any? turtles-here and (any? ecms-on neighbors or any? capillaries-on neighbors or any? fibroblasts-on neighbors) ]   ;; maybe will let basal cells overly both caps, fibs, and ecm, instead of just ecm
    if possible = nobody [
      set possible one-of neighbors4 with [(not any? turtles-here with [priority <= -2] and not any? ecms-here) and (any? ecms-on neighbors or any? capillaries-on neighbors or any? fibroblasts-on neighbors)]
      ]
    let displaced-neighbor nobody
    if not (possible = nobody) [
      if any? turtles-on possible [
        if any? basal-ktns-on possible [
          set displaced-neighbor one-of basal-ktns-on possible
          let recursion-depth 0
          ask displaced-neighbor [ displace-horizontally curr-x curr-y recursion-depth]
        ]
      ]
      if any? ((turtles-on possible) with [priority > 1]) [ ask turtles-on possible [die]]
      if not any? turtles-on possible [
        hatch-basal-ktns 1 [
          set priority -1 set shape "square" set tick-stagger random 360 move-to possible
        ]
      ]
    ]
  ]
end

to displace-horizontally [prior-x prior-y recursion-depth]     ;; recursive function called by hor-mitosis to displace cells in the way
  let rec-depth recursion-depth + 1
  let curr-priority priority
  let curr-y ycor
  let curr-x xcor

  let possible one-of neighbors4 with [not any? turtles-here and (any? ecms-on neighbors or any? capillaries-on neighbors or any? fibroblasts-on neighbors) and not (pxcor = prior-x and pycor = prior-y)]

  if possible = nobody [
    set possible one-of neighbors4 with [not any? turtles-here with [priority <= -2] and not any? ecms-here and (any? ecms-on neighbors or any? capillaries-on neighbors or any? fibroblasts-on neighbors) and not (pxcor = prior-x and pycor = prior-y)]
  ]

  if not (possible = nobody) [
    if any? basal-ktns-on possible and rec-depth < max-recursion-depth[
      ask turtles-on possible [ displace-horizontally curr-x curr-y rec-depth]
    ]
    if any? ((turtles-on possible) with [priority > 1])  [ ask turtles-on possible [ die]]
    if not any? turtles-on possible [
      move-to possible

    ]
  ]
end


to update-chemokine-gradient
  diffuse egf-level (8 / 9)
  diffuse pdgf-level (8 / 9)
  diffuse il6-level (8 / 9)
  diffuse il1-level (8 / 9)
  diffuse tnf-a-level (8 / 9)
  diffuse fgf-level (8 / 9)
  diffuse vegf-level (8 / 9)
  diffuse tgf-b-level (8 / 9)
  diffuse txa2-level (8 / 9)

  ;;use below if instead of disintegrating cytokine, it "disappears off screen" simulating cytokine entering other compartments
  ask patches with [pycor = min-pycor] [set egf-level 0 set pdgf-level 0 set il6-level 0 set il1-level 0 set tnf-a-level 0 set fgf-level 0 set vegf-level 0 set tgf-b-level 0 set txa2-level 0]

  ask patches [
    if not any? turtles-here and not any? turtles-on neighbors [
      set egf-level 0
      set pdgf-level 0 set il6-level 0 set il1-level 0 set tnf-a-level 0
      set fgf-level 0 set vegf-level 0 set tgf-b-level 0 set txa2-level 0
    ]

    set egf-level egf-level * 0.95
    set pdgf-level pdgf-level * 0.95
    set il6-level il6-level * 0.9
    set il1-level il1-level * 0.95
    set tnf-a-level tnf-a-level * 0.95
    set fgf-level fgf-level * 0.95
    set vegf-level vegf-level * 0.95
    set tgf-b-level tgf-b-level * 0.95
    set txa2-level txa2-level * 0.90

    ;;used to visualize cytokines based off of interface selector
    if visualize-cytokines = "egf" [
      set pcolor scale-color green egf-level 0.1 3
    ]
    if visualize-cytokines = "pdgf" [
      set pcolor scale-color green pdgf-level 0.1 3
    ]
    if visualize-cytokines = "il6" [
      set pcolor scale-color green il6-level 0.1 3
    ]
    if visualize-cytokines = "il1" [
      set pcolor scale-color green il1-level 0.1 3
    ]
    if visualize-cytokines = "tnf-a" [
      set pcolor scale-color green tnf-a-level 0.1 3
    ]
    if visualize-cytokines = "fgf" [
      set pcolor scale-color green fgf-level 0.1 3
    ]
    if visualize-cytokines = "vegf" [
      set pcolor scale-color green vegf-level 0.1 3
    ]
    if visualize-cytokines = "tgf-b" [
      set pcolor scale-color green tgf-b-level 0.1 3
    ]
    if visualize-cytokines = "txa2" [
      set pcolor scale-color green txa2-level 0.1 3
    ]
    if visualize-cytokines = "none" [
      set pcolor black
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
468
10
976
769
-1
-1
5.0
1
10
1
1
1
0
1
0
1
0
99
0
149
1
1
1
ticks
30.0

BUTTON
270
13
325
70
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
385
14
440
70
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

CHOOSER
296
163
443
208
visualize-cytokines
visualize-cytokines
"none" "egf" "pdgf" "il6" "il1" "txa2" "tnf-a" "fgf" "vegf" "tgf-b"
0

SWITCH
12
126
127
159
epithelialization
epithelialization
0
1
-1000

SWITCH
141
127
264
160
inflammation
inflammation
0
1
-1000

SWITCH
12
81
131
114
RandomRuns?
RandomRuns?
1
1
-1000

SLIDER
140
81
442
114
RandomSeed
RandomSeed
0
1000
420.0
1
1
NIL
HORIZONTAL

SWITCH
12
168
127
201
proliferation
proliferation
0
1
-1000

SWITCH
143
166
265
199
vascular
vascular
0
1
-1000

PLOT
13
549
238
699
Platelet-derived Cytokines
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"pdgf" 1.0 0 -16777216 true "" "plot sum ([pdgf-level] of patches)"
"txa2" 1.0 0 -2674135 true "" "plot sum ([txa2-level] of patches)"

BUTTON
328
14
383
70
NIL
burn
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
245
550
445
700
EGF
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot sum ([egf-level] of patches)"

PLOT
15
708
227
858
IL6
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot sum ([il6-level] of patches)"

PLOT
12
214
444
397
Neutrophil and Macrophage Counts
ticks
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"neutrophils" 1.0 0 -2674135 true "" "plot count neutrophils with [location = \"wound-bed\"]"
"macrophages" 1.0 0 -10899396 true "" "plot count macrophages with [location = \"wound-bed\"]"

INPUTBOX
11
10
61
70
unit-size
20.0
1
0
Number

PLOT
238
865
445
1015
VEGF
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot sum ([vegf-level] of patches)"

PLOT
16
865
226
1015
TGFb
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot sum ([tgf-b-level] of patches)"

PLOT
238
708
445
858
TNFa
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot sum ([tnf-a-level] of patches)"

INPUTBOX
64
11
155
71
num-hair-follicles
2.0
1
0
Number

SWITCH
295
125
443
158
debridement
debridement
0
1
-1000

INPUTBOX
157
12
268
72
num-days-to-simulate
21.0
1
0
Number

PLOT
12
404
444
543
Re-epithelialization Progress (%)
NIL
NIL
0.0
10.0
0.0
100.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot reepithelialization-progress"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="true">
    <setup>setup
burn</setup>
    <go>go</go>
    <metric>reepithelialization-progress</metric>
    <metric>percent-ecm-reproduced</metric>
    <metric>sum ([egf-level] of patches)</metric>
    <metric>sum ([il6-level] of patches)</metric>
    <metric>sum ([tnf-a-level] of patches)</metric>
    <metric>sum ([tgf-b-level] of patches)</metric>
    <metric>sum ([vegf-level] of patches)</metric>
    <metric>count neutrophils with [location = "wound-bed"]</metric>
    <metric>count macrophages with [location = "wound-bed"]</metric>
    <metric>sum ([hor-mitosis-rate] of basal-ktns)</metric>
    <metric>sum ([ecm-production-rate] of fibroblasts)</metric>
    <metric>count capillaries</metric>
    <steppedValueSet variable="RandomSeed" first="100" step="50" last="550"/>
    <enumeratedValueSet variable="num-hair-follicles">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="unit-size">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="RandomRuns?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="visualize-cytokines">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="vascular">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="epithelialization">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="inflammation">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proliferation">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="test of modularity" repetitions="1" runMetricsEveryStep="true">
    <setup>setup
burn</setup>
    <go>go</go>
    <metric>reepithelialization-progress</metric>
    <metric>percent-ecm-reproduced</metric>
    <metric>sum ([egf-level] of patches)</metric>
    <metric>sum ([il6-level] of patches)</metric>
    <metric>sum ([tnf-a-level] of patches)</metric>
    <metric>sum ([tgf-b-level] of patches)</metric>
    <metric>sum ([vegf-level] of patches)</metric>
    <metric>count neutrophils with [location = "wound-bed"]</metric>
    <metric>count macrophages with [location = "wound-bed"]</metric>
    <metric>sum ([hor-mitosis-rate] of basal-ktns)</metric>
    <metric>sum ([ecm-production-rate] of fibroblasts)</metric>
    <metric>count capillaries</metric>
    <enumeratedValueSet variable="RandomSeed">
      <value value="682"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="unit-size">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="RandomRuns?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="visualize-cytokines">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="vascular">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="epithelialization">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="inflammation">
      <value value="true"/>
    </enumeratedValueSet>
    <steppedValueSet variable="num-hair-follicles" first="2" step="2" last="4"/>
    <enumeratedValueSet variable="proliferation">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
