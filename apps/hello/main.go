// apps/hello - the Bucket-4 dogfood workload: a static "the deploy path works"
// page. Its only job is to prove the CI -> GHCR -> Dokploy chain end-to-end,
// so it renders the git SHA it was built from (stamped via -ldflags) - one
// glance at the page confirms which commit is live. stdlib only (licensing
// hygiene: nothing to audit), serves plain HTTP on :8080 behind Traefik TLS.
//
// -check flag = Docker HEALTHCHECK mode: the runtime image is FROM scratch
// (no shell, no curl), so the binary probes itself over loopback instead.
package main

import (
	"bytes"
	_ "embed"
	"flag"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"time"
)

//go:embed index.html
var pageTemplate string

// stamped at CI build time: -ldflags "-X main.version=<git sha>"
var version = "dev"

func main() {
	check := flag.Bool("check", false, "probe the running server and exit (HEALTHCHECK mode)")
	flag.Parse()

	if *check {
		client := &http.Client{Timeout: 3 * time.Second}
		resp, err := client.Get("http://127.0.0.1:8080/healthz")
		if err != nil || resp.StatusCode != http.StatusOK {
			os.Exit(1)
		}
		os.Exit(0)
	}

	hostname, _ := os.Hostname()
	data := struct {
		Version  string
		Started  string
		Hostname string
	}{version, time.Now().UTC().Format(time.RFC3339), hostname}

	// rendered once at startup - the page is a deploy receipt, not an app
	var page bytes.Buffer
	if err := template.Must(template.New("page").Parse(pageTemplate)).Execute(&page, data); err != nil {
		log.Fatalf("render: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		// no-store: after a redeploy the founder must see the new SHA, not a cache
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write(page.Bytes())
	})

	log.Printf("hello %s listening on :8080", version)
	server := &http.Server{
		Addr:              ":8080",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Fatal(server.ListenAndServe())
}
