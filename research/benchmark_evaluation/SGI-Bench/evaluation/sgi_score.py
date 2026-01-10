import json
import os
import sys
sys.path.append('.')
from utils import show_results


model_name = 'gpt-4.1'
discipline = "['all']"
discipline_list = ['astronomy', 'chemistry', 'earth', 'energy', 'information', 'life', 'material', 'mathematics', 'neuroscience', 'physics']
if len(sys.argv) > 1:
    model_name = sys.argv[1]
    sys.argv = sys.argv[1:]
if len(sys.argv) > 1:
    discipline = sys.argv[1]
    discipline_list = eval(discipline)
    sys.argv = sys.argv[1:]
print(f'Evaluating {model_name} in {discipline}')


with open(os.path.join('./task_1_deep_research/logs', f"{model_name.replace('/', '_')}{discipline}.json"), 'r', encoding='utf-8') as json_file:
    deep_research_logs = json.load(json_file)
print("Deep Research")
print("Exact Match (EM):", Deep_Research:=show_results(deep_research_logs, metric_name="exact_match", scale=100))
# print("Exact Match (EM):", show_results(deep_research_logs, metric_name="exact_match", category_name="type", scale=100))
# print("Exact Match (EM):", show_results(deep_research_logs, metric_name="exact_match", category_name="discipline", scale=100))
print("Step Level Acc (SLA):", show_results(deep_research_logs, metric_name="step_level_acc", scale=100))
print()


with open(os.path.join('./task_2_idea_generation/logs', f"{model_name.replace('/', '_')}{discipline}_evaluation.json"), 'r', encoding='utf-8') as json_file:
    idea_generation_logs = json.load(json_file)
print("Idea Generation")
print("Effectiveness:", show_results(idea_generation_logs, metric_name="effectiveness"))
print("Novelty:", show_results(idea_generation_logs, metric_name="novelty"))
print("Detailedness:", show_results(idea_generation_logs, metric_name="detailedness"))
print("Feasibility:", show_results(idea_generation_logs, metric_name="feasibility"))
print("Final Score:", Idea_Generation:=show_results(idea_generation_logs, metric_name="final_score"))
# print("Final Score:", show_results(idea_generation_logs, metric_name="final_score", category_name="discipline"))
print()


with open(os.path.join('./task_3_dry_experiment/logs', f"{model_name.replace('/', '_')}{discipline}.json"), 'r', encoding='utf-8') as json_file:
    dry_experiment_logs = json.load(json_file)
print("Dry Experiment")
print("PassAll@5:", Dry_Experiment:=show_results(dry_experiment_logs, metric_name="PassAll@5", scale=100))
# print("PassAll@5:", show_results(dry_experiment_logs, metric_name="PassAll@5", category_name="function_type", scale=100))
# print("PassAll@5:", show_results(dry_experiment_logs, metric_name="PassAll@5", category_name="discipline", scale=100))
print("PassAll@3:", show_results(dry_experiment_logs, metric_name="PassAll@3", scale=100))
print("PassAll@1:", show_results(dry_experiment_logs, metric_name="PassAll@1", scale=100))
print("Average Execution Time (AET):", show_results(dry_experiment_logs, metric_name="AET"))
print("Smooth Execution Rate (SER):", show_results(dry_experiment_logs, metric_name="SER", scale=100))
print()


with open(os.path.join('./task_3_wet_experiment/logs', f"{model_name.replace('/', '_')}{discipline}.json"), 'r', encoding='utf-8') as json_file:
    wet_experiment_logs = json.load(json_file)
print("Wet Experiment")
print("Action Sequence Similarity (SS):", show_results(wet_experiment_logs, metric_name="action_sequence_similarity", scale=100))
# print("Action Sequence Similarity (SS):", show_results(wet_experiment_logs, metric_name="action_sequence_similarity", category_name="discipline", scale=100))
print("Parameter Accuracy (PA):", show_results(wet_experiment_logs, metric_name="parameter_accuracy", scale=100))
# print("Parameter Accuracy (PA):", show_results(wet_experiment_logs, metric_name="parameter_accuracy", category_name="discipline", scale=100))
print("Final Score:", Wet_Experiment:=show_results(wet_experiment_logs, metric_name="final_score", scale=100))
print()


with open(os.path.join('./task_4_experimental_reasoning/logs', f"{model_name.replace('/', '_')}{discipline}.json"), 'r', encoding='utf-8') as json_file:
    experimental_reasoning_logs = json.load(json_file)
print("Experimental Reasoning")
print("Multi-Choice Accuracy (MCA):", Experimental_Reasoning:=show_results(experimental_reasoning_logs, metric_name="MCA", scale=100))
# print("Multi-Choice Accuracy (MCA):", show_results(experimental_reasoning_logs, metric_name="MCA", category_name="type", scale=100))
# print("Multi-Choice Accuracy (MCA):", show_results(experimental_reasoning_logs, metric_name="MCA", category_name="discipline", scale=100))
print("Reasoning Validity (RV):", show_results(experimental_reasoning_logs, metric_name="RV", scale=100))
print()

print(f"SGI_Score: {(Deep_Research+Idea_Generation+Dry_Experiment+Wet_Experiment+Experimental_Reasoning)/5:.2f}")