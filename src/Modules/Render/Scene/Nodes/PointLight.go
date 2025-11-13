components {
  id: "Light"
  component: "/src/Modules/Render/Scene/Nodes/PointLight.script"
}
embedded_components {
  id: "model"
  type: "model"
  data: "mesh: \"/builtins/assets/meshes/quad.dae\"\n"
  "name: \"{{NAME}}\"\n"
  "materials {\n"
  "  name: \"default\"\n"
  "  material: \"/src/Modules/Render/Scene/Materials/Billboard.material\"\n"
  "  textures {\n"
  "    sampler: \"tex0\"\n"
  "    texture: \"/src/Modules/Render/Scene/Textures/render_light.png\"\n"
  "  }\n"
  "}\n"
  ""
}
embedded_components {
  id: "model1"
  type: "model"
  data: "mesh: \"/src/Modules/Render/Scene/Meshes/Light.glb\"\n"
  "name: \"{{NAME}}\"\n"
  "materials {\n"
  "  name: \"default\"\n"
  "  material: \"/src/Modules/Render/Scene/Materials/Sphere.material\"\n"
  "}\n"
  ""
}
