/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Technical storage drivers (snapshots, blobs).
module neko.objects.persistence.storages;

public {
  import neko.objects.persistence.storages.blobs;
  import neko.objects.persistence.storages.json_file;
  import neko.objects.persistence.storages.memory;
  import neko.objects.persistence.storages.snapshot_store;
}
