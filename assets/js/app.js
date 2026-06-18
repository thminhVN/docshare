// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Hook bridging the sandboxed document iframe and the LiveView.
const Hooks = {}
Hooks.DocFrame = {
  mounted() {
    this.lastCounts = {}
    this.lastSelect = null

    // Messages coming up from the iframe content.
    this.onMessage = (e) => {
      if (this.el.contentWindow && e.source !== this.el.contentWindow) return
      const d = e.data || {}
      if (d.type === "ds:select") {
        this.pushEvent("select_anchor", {anchor: d.anchor, label: d.label})
      } else if (d.type === "ds:ready") {
        this.send({type: "ds:counts", counts: this.lastCounts})
        if (this.lastSelect) this.send({type: "ds:select", anchor: this.lastSelect})
      }
    }
    window.addEventListener("message", this.onMessage)

    // Events pushed down from the server.
    this.handleEvent("ds:counts", ({counts}) => {
      this.lastCounts = counts || {}
      this.send({type: "ds:counts", counts: this.lastCounts})
    })
    this.handleEvent("ds:select", ({anchor}) => {
      this.lastSelect = anchor
      this.send({type: "ds:select", anchor})
    })
  },
  send(msg) {
    if (this.el.contentWindow) this.el.contentWindow.postMessage(msg, "*")
  },
  destroyed() {
    window.removeEventListener("message", this.onMessage)
  }
}

// Formatting toolbar for the comment box: wraps the current selection with the
// matching markdown markers (the body is still stored/rendered as markdown).
Hooks.CommentToolbar = {
  mounted() {
    this.onClick = (e) => {
      const btn = e.target.closest("[data-md]")
      if (!btn) return
      e.preventDefault()
      const ta = this.el.querySelector("textarea")
      if (!ta) return
      this.format(ta, btn.getAttribute("data-md"))
    }
    this.el.addEventListener("click", this.onClick)

    // Clear the box once the server confirms the comment was saved.
    this.handleEvent("comment:reset", () => {
      const ta = this.el.querySelector("textarea")
      if (ta) ta.value = ""
    })
  },
  format(ta, kind) {
    const start = ta.selectionStart
    const end = ta.selectionEnd
    const sel = ta.value.slice(start, end)

    let before, after, placeholder
    if (kind === "bold") { before = "**"; after = "**"; placeholder = "bold text" }
    else if (kind === "italic") { before = "*"; after = "*"; placeholder = "italic text" }
    else if (kind === "code") { before = "`"; after = "`"; placeholder = "code" }
    else if (kind === "link") { before = "["; after = "](url)"; placeholder = "link text" }
    else return

    const inner = sel || placeholder
    const insert = before + inner + after
    ta.setRangeText(insert, start, end, "end")

    // Select the inner text (or, for links, the url) so it's easy to overwrite.
    ta.focus()
    if (kind === "link" && !sel) {
      const urlStart = start + before.length + inner.length + 2 // past "]("
      ta.setSelectionRange(urlStart, urlStart + 3) // selects "url"
    } else if (!sel) {
      ta.setSelectionRange(start + before.length, start + before.length + inner.length)
    } else {
      ta.setSelectionRange(start + insert.length, start + insert.length)
    }
    ta.dispatchEvent(new Event("input", {bubbles: true}))
  },
  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  }
}

// Sidebar in the compare modal: clicking a change scrolls the diff iframe to it.
Hooks.DiffNav = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-step]")
      if (!btn) return
      const frame = document.getElementById("diff-frame")
      if (frame && frame.contentWindow) {
        frame.contentWindow.postMessage({type: "ds:goto", step: btn.getAttribute("data-step")}, "*")
      }
    })
  }
}

// Copies the value/text of the element named in data-target to the clipboard.
Hooks.CopyButton = {
  mounted() {
    this.el.addEventListener("click", () => {
      const node = document.querySelector(this.el.getAttribute("data-target"))
      if (!node) return
      const text = node.value !== undefined ? node.value : node.textContent
      navigator.clipboard.writeText(text).then(() => {
        const original = this.el.textContent
        this.el.textContent = "Copied!"
        setTimeout(() => (this.el.textContent = original), 1500)
      })
    })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  hooks: Hooks,
  params: {_csrf_token: csrfToken}
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

