package main

import "embed"

//go:embed all:web/dist
var embeddedWebAssets embed.FS
