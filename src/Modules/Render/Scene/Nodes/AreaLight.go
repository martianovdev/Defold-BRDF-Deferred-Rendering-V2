components {
  id: "Script"
  component: "/src/Modules/Render/Scene/Nodes/AreaLight.script"
}
embedded_components {
  id: "model"
  type: "model"
  data: "mesh: \"/src/Assets/Meshes/plane.glb\"\n"
  "name: \"{{NAME}}\"\n"
  "materials {\n"
  "  name: \"default\"\n"
  "  material: \"/src/Modules/Render/Scene/Materials/AreaLight.material\"\n"
  "  textures {\n"
  "    sampler: \"albedo\"\n"
  "    texture: \"/src/Modules/Render/Scene/Textures/area_light.png\"\n"
  "  }\n"
  "}\n"
  ""
}
