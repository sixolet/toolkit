# Your Great Aunt Pam Gave you her Toolkit

She's running a whole makerspace now, she doesn't need it.

`toolkit` is a mod for Monome Norns.

Aunt Pam's `toolkit` contains a pile of LFOs, rhythms, sequencers, and mults. Each can be used to modulate other parameters. When you're modulating one parameter with more than one modulator, the modulations mix additively into their target, and you can still also midi-map or change that parameter directly (and it'll change the "core" unmodulated value, without changing the modulations).

You must first install and activate https://github.com/sixolet/matrix !!! It's now a dependency!

Then you can install this mod and it'll work.

## LFOs

Four shapes: sine, tri/saw, pulse, random. In the tri/saw shape the “width” parameter controls where in the wave shape the peak is.

## Rhythms

You pick the division in terms of type of note — 1/4 is quarter notes, for example. Then you pick a length, an offset, and a fill for the euclidean parameters. The fill and offset are defined as a proportion of the length filled, since I didn’t want to worry about undefined values while length changed.

The targets for rhythm generators are binary parameters and triggers. The binary parameters will be set to 1 for every step the euclidean generator contains a beat, and off when it doesn’t. The triggers will be triggered on every step the euclidean generator contains a beat.

You can also pick a swing. Right now there’s some kind of weirdness in lattice that makes swung eighth notes not line up with quarter notes, maybe wait for that to be fixed before using those in combination.

Rhythms can target any number of trigger and boolean parameters. You pick them from a checklist.

## Sequencers

Each sequencer has up to 16 steps, and has a trigger to advance and one to reset. You can patch rhythms to these advance or reset triggers if you like. They also have `zero` and `shred` parameters. These control, respectively, the probability that the sequencer will zero a step upon leaving it, or that the sequencer will randomize a step upon leaving it. These allow making sequences that mostly repeat but slowly vary.

## Macros

Macros are parameters that provide their value as a modulation source. Midi map them, or adjust them using the encoders, or whatever you like.
