## Saves a code-built scene. Root scripts that reference autoloads cannot load in `-s` mode, so
## the root script is attached by editing the saved text scene.
class_name SceneIO
extends RefCounted


static func save(root: Node, path: String, script_path: String = "") -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		return err
	err = ResourceSaver.save(packed, path)
	if err != OK or script_path == "":
		return err
	var text := FileAccess.get_file_as_string(path)
	var header_end := text.find("\n\n")
	text = text.substr(0, header_end + 2) + '[ext_resource type="Script" path="%s" id="bp_root_script"]\n\n' % script_path + text.substr(header_end + 2)
	var re := RegEx.create_from_string('(\\[node name="%s" type="[A-Za-z0-9]+"[^\\]]*\\]\\n)' % root.name)
	text = re.sub(text, '$1script = ExtResource("bp_root_script")\n')
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	return OK
