// Fill in the download section from the newest GitHub release. Without
// JavaScript, or if the API is unavailable (rate limits), the buttons
// still point at the Releases page.
(function () {
  "use strict";
  var REPO = "sahil-mpatki/Shell";
  var API = "https://api.github.com/repos/" + REPO;

  function $(id) { return document.getElementById(id); }

  function size(bytes) {
    var units = ["B", "KB", "MB", "GB"];
    var i = 0;
    while (bytes >= 1024 && i < units.length - 1) { bytes /= 1024; i++; }
    return bytes.toFixed(i >= 2 ? 1 : 0) + " " + units[i];
  }

  function date(iso) {
    return new Date(iso).toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" });
  }

  function getJSON(url) {
    return fetch(url, { headers: { Accept: "application/vnd.github+json" } }).then(function (r) {
      if (!r.ok) throw new Error(url + ": " + r.status);
      return r.json();
    });
  }

  // The newest stable release; if there is none yet, the newest of any kind.
  function latestRelease() {
    return getJSON(API + "/releases/latest").catch(function () {
      return getJSON(API + "/releases?per_page=5").then(function (list) {
        var published = list.filter(function (r) { return !r.draft; });
        if (!published.length) throw new Error("no releases");
        return published[0];
      });
    });
  }

  function render(rel) {
    var assets = rel.assets || [];
    var iso = assets.filter(function (a) { return /\.iso$/.test(a.name); })[0];
    // iso.yml splits ISOs over 2 GiB with `split -d`: NAME.iso.part00, part01...
    var parts = assets.filter(function (a) { return /\.iso\.part\d+$/.test(a.name); });
    var isoBytes = iso ? iso.size : parts.reduce(function (n, a) { return n + a.size; }, 0);

    $("rel-name").textContent = rel.name || rel.tag_name;
    $("rel-meta").textContent = rel.tag_name + " · " + date(rel.published_at) +
      (isoBytes ? " · " + size(isoBytes) : "") + (rel.prerelease ? " · pre-release" : "");
    $("hero-release").textContent = "Latest: " + rel.tag_name + ", released " + date(rel.published_at);

    var list = $("rel-assets");
    list.textContent = "";
    assets.forEach(function (a) {
      var li = document.createElement("li");
      var link = document.createElement("a");
      link.href = a.browser_download_url;
      link.textContent = a.name;
      var s = document.createElement("span");
      s.className = "size";
      s.textContent = size(a.size);
      li.appendChild(link);
      li.appendChild(s);
      list.appendChild(li);
    });

    var target = iso ? iso.browser_download_url : rel.html_url;
    $("rel-iso").href = target;
    $("hero-download").href = target;
    $("rel-iso").textContent = iso ? "Download ISO" : "Get the ISO parts";
    if (!iso && parts.length) {
      var base = parts[0].name.replace(/\.part\d+$/, "");
      $("rel-join-cmd").textContent = "cat " + base + ".part* > " + base + "\nsha256sum -c " + base + ".sha256";
      $("rel-join").hidden = false;
    }
  }

  latestRelease().then(render).catch(function () {
    $("rel-meta").textContent = "See the Releases page for the newest ISO.";
  });
})();
